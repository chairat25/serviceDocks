import Darwin
import Foundation

enum ProcessRunnerError: Error, LocalizedError {
    case spawnFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .spawnFailed(let code): "Could not start process: \(String(cString: strerror(code)))"
        }
    }
}

/// A child process in its own process group, so stopping it also stops
/// everything it spawned (yarn → node → esbuild …) and frees its ports.
@MainActor
final class ProcessRunner {
    /// Group members still alive after the leader exits get this long before SIGKILL.
    static let orphanGrace: Duration = .seconds(2)
    /// How long to wait for the pipe to drain once the group is gone.
    static let drainTimeout: Duration = .seconds(1)
    private static let pollInterval: Duration = .milliseconds(100)

    let pid: pid_t
    private let output: FileHandle
    private let onExit: @Sendable @MainActor (Int32) -> Void
    private var exitSource: DispatchSourceProcess?
    private var exitCode: Int32?
    private let mailbox = OutputMailbox()
    private var isOutputClosed = false
    private var isFinishing = false

    /// - Parameters:
    ///   - onOutput: raw bytes from stdout+stderr (one pipe, so order is kept), on the main actor.
    ///   - onExit: exit code of the leader (negative = signal), delivered once on the main actor after the
    ///     whole group is gone and its output has drained — no output arrives after it.
    static func launch(arguments: [String], environment: [String: String],
                       onOutput: @escaping @Sendable @MainActor (Data) -> Void,
                       onExit: @escaping @Sendable @MainActor (Int32) -> Void) throws -> ProcessRunner {
        let output = Pipe()
        let pid = try spawn(arguments: arguments, environment: environment, output: output)
        try? output.fileHandleForWriting.close()
        return ProcessRunner(pid: pid, output: output.fileHandleForReading, onOutput: onOutput, onExit: onExit)
    }

    private init(pid: pid_t, output: FileHandle, onOutput: @escaping @Sendable @MainActor (Data) -> Void,
                 onExit: @escaping @Sendable @MainActor (Int32) -> Void) {
        self.pid = pid
        self.output = output
        self.onExit = onExit

        // The reader thread only drops bytes into a bounded mailbox; the main actor drains it in one go.
        // A chatty service therefore costs one main-thread hop per drain, not one per read, and a flood
        // the UI cannot keep up with is skipped (with a note) instead of piling up in memory.
        let mailbox = self.mailbox
        output.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            guard mailbox.push(data) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.drain(into: onOutput) }
            }
        }

        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.leaderExited() }
        }
        source.resume()
        exitSource = source
    }

    private func drain(into onOutput: @MainActor (Data) -> Void) {
        let batch = mailbox.take()
        guard !isOutputClosed else { return }
        if batch.droppedBytes > 0 {
            onOutput(Data("[ServiceDock] output too fast — skipped \(batch.droppedBytes / 1024) KB\n".utf8))
        }
        if !batch.data.isEmpty { onOutput(batch.data) }
        if batch.isEOF { isOutputClosed = true }
    }

    /// Asks the whole process group to stop.
    func terminate() { kill(-pid, SIGTERM) }

    /// Kills the whole process group.
    func forceKill() { kill(-pid, SIGKILL) }

    /// Reaps the leader so it does not linger as a zombie inside the group.
    var isGroupAlive: Bool {
        reap()
        return kill(-pid, 0) == 0
    }

    @discardableResult
    private func reap() -> Int32? {
        if let exitCode { return exitCode }
        var status: Int32 = 0
        guard waitpid(pid, &status, WNOHANG) == pid else { return nil }
        exitCode = Self.exitCode(fromWaitStatus: status)
        return exitCode
    }

    private func leaderExited() {
        guard let code = reap(), !isFinishing else { return }
        isFinishing = true
        exitSource?.cancel()
        exitSource = nil
        Task { await finish(code: code) }
    }

    /// The leader is gone: clean up any orphans (e.g. node outliving yarn) so the port is freed,
    /// let the last output drain, then report.
    private func finish(code: Int32) async {
        if isGroupAlive {
            terminate()
            await waitUntil(timeout: Self.orphanGrace) { !self.isGroupAlive }
            if isGroupAlive { forceKill() }
        }
        await waitUntil(timeout: Self.drainTimeout) { self.isOutputClosed }
        output.readabilityHandler = nil
        try? output.close()
        isOutputClosed = true
        onExit(code)
    }

    private func waitUntil(timeout: Duration, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : -signal
    }

    private static func spawn(arguments: [String], environment: [String: String], output: Pipe) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, 1)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, 2)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // New process group (pgid = child pid); close every fd not listed in `actions`;
        // reset signal dispositions and mask so SIGTERM/SIGINT are never inherited as ignored/blocked.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                    | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var defaultSignals = sigset_t()
        [SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGPIPE, SIGCHLD].forEach { sigaddset(&defaultSignals, $0) }
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)

        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp)
        guard result == 0 else { throw ProcessRunnerError.spawnFailed(result) }
        return pid
    }
}

/// Hands output from the reader thread to the main actor. Bounded: past `capacity` the oldest bytes go.
private final class OutputMailbox: @unchecked Sendable {
    static let capacity = 2 * 1024 * 1024

    struct Batch {
        let data: Data
        let droppedBytes: Int
        let isEOF: Bool
    }

    private let lock = NSLock()
    private var data = Data()
    private var droppedBytes = 0
    private var isEOF = false
    private var isDrainScheduled = false

    /// Returns true when the caller must schedule a drain (none is pending). Empty `chunk` = EOF.
    func push(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if chunk.isEmpty {
            isEOF = true
        } else {
            data.append(chunk)
            if data.count > Self.capacity {
                let excess = data.count - Self.capacity
                data = data.suffix(Self.capacity)
                droppedBytes += excess
            }
        }
        guard !isDrainScheduled else { return false }
        isDrainScheduled = true
        return true
    }

    func take() -> Batch {
        lock.lock()
        defer { lock.unlock() }
        let batch = Batch(data: data, droppedBytes: droppedBytes, isEOF: isEOF)
        data = Data()
        droppedBytes = 0
        isDrainScheduled = false
        return batch
    }
}
