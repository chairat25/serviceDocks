import Foundation
import Observation
import ServiceDockCore

/// Live state of one service: its process, status, logs and resource usage.
@Observable @MainActor
final class ServiceRuntime: Identifiable {
    /// Grace period before a stopping process group is killed outright.
    static let killTimeout: Duration = .seconds(5)
    /// Output is shown in batches this often, so a chatty service doesn't redraw the UI per chunk.
    static let flushInterval: Duration = .milliseconds(100)
    static let maxLineLength = 2000
    /// When to look at which ports a running service listens on (after it became ready).
    private static let portLearningDelays: [Duration] = [.seconds(3), .seconds(20)]
    /// `.env` files are checked on every Nth stats refresh — they rarely change.
    private static let envCheckEvery = 3

    private(set) var config: ServiceConfig
    private(set) var status: ServiceStatus = .stopped
    private(set) var logs = LogBuffer()
    private(set) var startedAt: Date?
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryKB = 0
    /// `.env*` files edited since the process started — a restart is needed to pick them up.
    private(set) var changedEnvFiles: [String] = []
    /// A real "ready" line was printed since the last start (unlike `.running`, not set by the grace period).
    private(set) var hasSeenReadyLine = false

    @ObservationIgnored private var runner: ProcessRunner?
    /// Changes on every launch so late callbacks from a previous process are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var splitter = LineSplitter()
    @ObservationIgnored private var envSnapshot: EnvWatch.Snapshot = [:]
    @ObservationIgnored private var restartAfterExit = false
    @ObservationIgnored private var killTask: Task<Void, Never>?
    /// Frees ports, then spawns; non-nil only while that is in progress.
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var learnTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var pendingLines: [String] = []
    @ObservationIgnored private var refreshCount = 0
    @ObservationIgnored private var readyMatcher: ReadyMatcher
    @ObservationIgnored private let emit: @MainActor (ServiceRuntime, [String], LogLevel?) -> [LogLine]
    @ObservationIgnored private let registry: RunRegistry
    @ObservationIgnored private let protectedGroups: @MainActor () -> Set<Int32>
    @ObservationIgnored private let onConfigChange: @MainActor () -> Void

    nonisolated var id: UUID { configID }
    @ObservationIgnored private nonisolated let configID: UUID

    /// - Parameters:
    ///   - emit: turns raw text into numbered `LogLine`s (and mirrors them into the combined log).
    ///     A `nil` level means "classify from the text".
    ///   - protectedGroups: process groups of other managed services, never killed by port clean-up.
    ///   - onConfigChange: called after the runtime changes its own config (learned ports) so it gets saved.
    init(config: ServiceConfig, registry: RunRegistry,
         protectedGroups: @escaping @MainActor () -> Set<Int32>,
         onConfigChange: @escaping @MainActor () -> Void,
         emit: @escaping @MainActor (ServiceRuntime, [String], LogLevel?) -> [LogLine]) {
        self.config = config
        self.configID = config.id
        self.readyMatcher = ReadyMatcher(customPattern: config.readyPattern)
        self.registry = registry
        self.protectedGroups = protectedGroups
        self.onConfigChange = onConfigChange
        self.emit = emit
    }

    /// Process group id while a process exists.
    var processGroup: Int32? { runner?.pid }

    var cpu: Double { cpuHistory.last ?? 0 }

    /// Most recent error lines still in the buffer, oldest first.
    func recentErrors(limit: Int) -> [LogLine] {
        Array(logs.lines.lazy.reversed().filter { $0.level == .error }.prefix(limit).reversed())
    }
    var hasProblem: Bool {
        if case .down = status { return true }
        return logs.errorCount > 0
    }

    /// What the staged start-up should conclude about this service.
    /// `wasAlreadyUp` services (started before Run All) count as ready once they are `.running`.
    func startSignal(wasAlreadyUp: Bool) -> StageGate.Signal {
        switch status {
        case .stopped, .stopping, .down: .failed
        case .running where wasAlreadyUp: .ready
        case .starting, .running: hasSeenReadyLine ? .ready : .pending
        }
    }

    var directory: String { config.expandedPath(home: NSHomeDirectory()) }
    var displayPath: String { ServiceConfig.abbreviate(directory, home: NSHomeDirectory()) }

    func update(config newConfig: ServiceConfig) {
        if newConfig.readyPattern != config.readyPattern {
            readyMatcher = ReadyMatcher(customPattern: newConfig.readyPattern)
        }
        config = newConfig
    }

    // MARK: - Lifecycle

    func start() {
        guard !status.isAlive else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            note("Folder not found: \(directory)", level: .error)
            status = .down(exitCode: 1)
            return
        }

        generation += 1
        let launched = generation
        status = .starting
        startedAt = Date()
        hasSeenReadyLine = false
        cpuHistory = []
        refreshCount = 0
        envSnapshot = EnvWatch.snapshot(of: directory)
        changedEnvFiles = []

        let ports = config.portsToFree
        guard !ports.isEmpty else { return launch(generation: launched) }
        launchTask = Task { [weak self] in
            await self?.freePortsThenLaunch(ports, generation: launched)
        }
    }

    func stop() {
        restartAfterExit = false
        if case .down = status { status = .stopped }
        requestStop()
    }

    /// Stops, waits for the old process group to exit (so ports are free), then starts again.
    func restart() {
        guard status.isAlive else { return start() }
        restartAfterExit = true
        requestStop()
    }

    /// Synchronous best-effort kill used when the app quits.
    func terminateForQuit() -> ProcessRunner? {
        restartAfterExit = false
        launchTask?.cancel()
        generation += 1
        runner?.terminate()
        return runner
    }

    func clearLogs() {
        pendingLines = []
        logs.clear()
    }

    private func freePortsThenLaunch(_ ports: [Int], generation launched: Int) async {
        let notes = await PortTools.free(ports: ports, protectedGroups: protectedGroups())
        guard !Task.isCancelled, generation == launched else { return }
        notes.forEach { note($0.text, level: $0.level) }
        launchTask = nil
        launch(generation: launched)
    }

    private func launch(generation launched: Int) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let arguments = ShellCommand.arguments(shell: shell, directory: directory, command: config.command)
        note("▶ \(config.command)   (\(displayPath))", level: .info)
        do {
            runner = try ProcessRunner.launch(
                arguments: arguments,
                environment: ProcessInfo.processInfo.environment,
                onOutput: { [weak self] data in
                    guard let self, self.generation == launched else { return }
                    self.receive(data)
                },
                onExit: { [weak self] code in
                    guard let self, self.generation == launched else { return }
                    self.processExited(code: code)
                }
            )
        } catch {
            note(error.localizedDescription, level: .error)
            status = .down(exitCode: 1)
            return
        }
        if let runner { registry.record(pid: runner.pid, name: config.name) }
        splitter = LineSplitter()
    }

    private func requestStop() {
        guard status != .stopping else { return }
        guard let runner else {
            // Still clearing ports: cancel the launch instead of waiting for a process that doesn't exist yet.
            guard launchTask != nil else { return }
            launchTask?.cancel()
            launchTask = nil
            generation += 1
            status = .stopped
            startedAt = nil
            note("■ Cancelled before it started", level: .info)
            if restartAfterExit {
                restartAfterExit = false
                start()
            }
            return
        }
        status = .stopping
        note("■ Stopping…", level: .info)
        runner.terminate()
        let pid = runner.pid
        killTask = Task { [weak self] in
            try? await Task.sleep(for: Self.killTimeout)
            guard !Task.isCancelled, let self, self.runner?.pid == pid else { return }
            self.note("Process did not exit in time — killing it.", level: .warn)
            self.runner?.forceKill()
        }
    }

    // MARK: - Process events

    private func receive(_ data: Data) {
        let (next, lines) = splitter.feeding(data)
        splitter = next
        append(raw: lines)
    }

    /// Cleans lines, spots the ready line right away (start-up ordering depends on it), and queues
    /// the lines for the next batched flush.
    private func append(raw: [String]) {
        let cleaned = raw.map(LogClassifier.clean).filter(LogClassifier.hasContent)
        guard !cleaned.isEmpty else { return }

        if !hasSeenReadyLine, cleaned.contains(where: readyMatcher.isReady) {
            hasSeenReadyLine = true
            if status == .starting { status = .running }
            learnPorts()
        }

        pendingLines.append(contentsOf: cleaned.map { LogClassifier.clamp($0, limit: Self.maxLineLength) })
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            if !Task.isCancelled { self?.flushPending() }
        }
    }

    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingLines.isEmpty else { return }
        let batch = pendingLines
        pendingLines = []
        logs.append(emit(self, batch, nil))
    }

    private func processExited(code: Int32) {
        append(raw: splitter.flushed())
        flushPending()
        splitter = LineSplitter()
        killTask?.cancel()
        killTask = nil
        learnTask?.cancel()
        learnTask = nil
        if let runner { registry.forget(pid: runner.pid) }
        runner = nil
        startedAt = nil
        memoryKB = 0
        changedEnvFiles = []
        let wasStopping = status == .stopping
        status = wasStopping ? .stopped : .down(exitCode: code)
        note(wasStopping ? "■ Stopped" : "✖ Exited unexpectedly (\(status.label))", level: wasStopping ? .info : .error)

        if restartAfterExit {
            restartAfterExit = false
            start()
        }
    }

    /// Remembers the ports this service listens on, so the next start can clear them. Two samples:
    /// shortly after ready, and later for services that open extra ports (gRPC, debugger) afterwards.
    private func learnPorts() {
        guard learnTask == nil, config.freesPortsOnStart else { return }
        let launched = generation
        learnTask = Task { [weak self] in
            for delay in Self.portLearningDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.generation == launched, let group = self.processGroup else { return }
                let found = await PortTools.listeningPorts(ofGroup: group)
                guard !Task.isCancelled, self.generation == launched else { return }
                self.remember(ports: found)
            }
        }
    }

    private func remember(ports found: [Int]) {
        let merged = PortList.merge(config.learnedPorts, with: found)
        guard merged != config.learnedPorts else { return }
        var updated = config
        updated.learnedPorts = merged
        config = updated
        onConfigChange()
    }

    // MARK: - Periodic refresh

    /// Called every few seconds with fresh `ps` numbers.
    func refresh(stats: [Int32: ProcessStats.Sample], now: Date) {
        guard let runner, status.isAlive else { return }
        let sample = stats[runner.pid] ?? ProcessStats.Sample(cpu: 0, memoryKB: 0)
        cpuHistory = ProcessStats.appending(sample.cpu, to: cpuHistory)
        memoryKB = sample.memoryKB

        if status == .starting, let startedAt, now.timeIntervalSince(startedAt) >= Readiness.gracePeriod {
            status = .running
            learnPorts()
        }
        refreshCount += 1
        if status != .stopping, refreshCount % Self.envCheckEvery == 0 {
            let changed = EnvWatch.changedFiles(from: envSnapshot, to: EnvWatch.snapshot(of: directory))
            if changed != changedEnvFiles { changedEnvFiles = changed }
        }
    }

    private func note(_ text: String, level: LogLevel) {
        flushPending()
        logs.append(emit(self, [text], level))
    }
}
