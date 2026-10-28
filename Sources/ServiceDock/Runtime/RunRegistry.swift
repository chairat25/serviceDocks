import Foundation
import ServiceDockCore

/// Remembers which process groups ServiceDock started (on disk), so groups orphaned by a
/// SIGKILL / crash of the app can be stopped on the next launch instead of holding ports.
@MainActor
final class RunRegistry {
    private static let termGrace: TimeInterval = 2

    private let url: URL
    private var records: [RunRecord]

    init(url: URL = RunRegistry.defaultURL) {
        self.url = url
        self.records = Self.load(from: url)
    }

    static var defaultURL: URL {
        ConfigStore.defaultURL.deletingLastPathComponent().appendingPathComponent("running.json")
    }

    func record(pid: pid_t, name: String) {
        guard let startTime = Self.startTime(of: pid) else { return }
        records = records.filter { $0.pgid != pid } + [RunRecord(pgid: pid, startTime: startTime, name: name)]
        save()
    }

    func forget(pid: pid_t) {
        records = records.filter { $0.pgid != pid }
        save()
    }

    /// Stops groups left over from a previous run. Returns the names that were still alive.
    @discardableResult
    func reapStale() -> [String] {
        let stale = records.filter { StaleProcess.isSame($0, currentStartTime: Self.startTime(of: $0.pgid)) }
        stale.forEach { kill(-$0.pgid, SIGTERM) }
        let deadline = Date().addingTimeInterval(Self.termGrace)
        while Date() < deadline, stale.contains(where: { kill(-$0.pgid, 0) == 0 }) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        stale.filter { kill(-$0.pgid, 0) == 0 }.forEach { kill(-$0.pgid, SIGKILL) }
        if !stale.isEmpty {
            logger.notice("Stopped leftover services from a previous run: \(stale.map(\.name).joined(separator: ", "), privacy: .public)")
        }
        records = []
        save()
        return stale.map(\.name)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        } catch {
            logger.error("Could not save running.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [RunRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([RunRecord].self, from: data)
        } catch {
            logger.error("Ignoring unreadable running.json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Start time of a pid as printed by `ps`, or nil when it no longer exists.
    private static func startTime(of pid: pid_t) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "lstart=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.error("ps failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return StaleProcess.startTime(fromPS: String(decoding: data, as: UTF8.self))
    }
}
