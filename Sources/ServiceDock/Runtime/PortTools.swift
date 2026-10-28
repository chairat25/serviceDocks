import Darwin
import Foundation
import ServiceDockCore

/// One line to show in a service's log about what port clean-up did.
struct PortNote: Sendable {
    let text: String
    let level: LogLevel
}

/// Finds and stops leftover processes that still hold a service's ports.
enum PortTools {
    private static let lsof = "/usr/sbin/lsof"
    private static let termGrace: Duration = .seconds(2)
    private static let killGrace: Duration = .seconds(1)
    private static let pollInterval: Duration = .milliseconds(150)

    /// Ports a process group is listening on (TCP).
    static func listeningPorts(ofGroup pgid: Int32) async -> [Int] {
        let output = await run(lsof, ["-nP", "-a", "-g", "\(pgid)", "-iTCP", "-sTCP:LISTEN", "-Fn"])
        return LsofParser.listeningPorts(fromFn: output)
    }

    /// Stops whatever listens on `ports`, except processes in `protectedGroups` (other managed services).
    static func free(ports: [Int], protectedGroups: Set<Int32>) async -> [PortNote] {
        let holders = await listeners(on: ports)
        guard !holders.isEmpty else { return [] }

        var notes: [PortNote] = []
        var targets: [(pid: Int32, group: Int32, ports: [Int], name: String)] = []
        for (pid, held) in holders.sorted(by: { $0.key < $1.key }) {
            let group = getpgid(pid)
            if pid == getpid() || group == getpgrp() { continue }
            if protectedGroups.contains(group) {
                notes.append(PortNote(text: "Port \(PortList.format(held)) is held by another service managed here (PID \(pid)) — left running.",
                                      level: .warn))
                continue
            }
            targets.append((pid, group, held, await processName(pid)))
        }
        guard !targets.isEmpty else { return notes }

        for target in targets { signal(target, SIGTERM) }
        if await !waitUntilFree(targets.map(\.pid), ports: ports, timeout: termGrace) {
            for target in targets { signal(target, SIGKILL) }
            _ = await waitUntilFree(targets.map(\.pid), ports: ports, timeout: killGrace)
        }

        let stillHeld = await listeners(on: ports)
        for target in targets {
            let name = target.name
            let isFreed = stillHeld[target.pid] == nil
            notes.append(PortNote(
                text: isFreed
                    ? "Stopped leftover \(name) (PID \(target.pid)) that was holding port \(PortList.format(target.ports))."
                    : "Could not stop \(name) (PID \(target.pid)) holding port \(PortList.format(target.ports)).",
                level: isFreed ? .info : .warn))
        }
        return notes
    }

    // MARK: - Private

    /// pid → wanted ports it listens on.
    private static func listeners(on ports: [Int]) async -> [Int32: [Int]] {
        let selectors = ports.flatMap { ["-iTCP:\($0)"] }
        let output = await run(lsof, ["-nP", "-sTCP:LISTEN", "-Fpn"] + selectors)
        return LsofParser.portsByPid(fromFpn: output, wanted: Set(ports))
    }

    private static func signal(_ target: (pid: Int32, group: Int32, ports: [Int], name: String), _ signal: Int32) {
        // Whole group, like Ctrl-C would, so a parent wrapper (yarn) can't respawn the child.
        kill(target.group > 1 ? -target.group : target.pid, signal)
    }

    private static func waitUntilFree(_ pids: [Int32], ports: [Int], timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let held = await listeners(on: ports)
            if pids.allSatisfy({ held[$0] == nil }) { return true }
            try? await Task.sleep(for: pollInterval)
        }
        return false
    }

    private static func processName(_ pid: Int32) async -> String {
        let name = await run("/bin/ps", ["-o", "comm=", "-p", "\(pid)"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "process" : (name as NSString).lastPathComponent
    }

    /// Runs a tool off the main thread and returns stdout. A non-zero exit (e.g. lsof finding nothing) is normal.
    private static func run(_ path: String, _ arguments: [String]) async -> String {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                logger.error("\(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return ""
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
