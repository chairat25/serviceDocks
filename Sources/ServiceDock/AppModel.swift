import AppKit
import Foundation
import Observation
import os
import ServiceDockCore

let logger = Logger(subsystem: "com.pond.servicedock", category: "app")

@Observable @MainActor
final class AppModel {
    static let statsInterval: Duration = .seconds(3)
    static let combinedCapacity = 6000
    private static let pollInterval: Duration = .milliseconds(200)
    private static let stopAllTimeout: Duration = .seconds(15)

    private(set) var runtimes: [ServiceRuntime] = []
    /// Removed services whose process is still shutting down; kept alive so the kill timeout still fires.
    @ObservationIgnored private var retiring: [ServiceRuntime] = []
    /// Every service's output interleaved, for the All Services monitor.
    private(set) var combinedLogs = LogBuffer(capacity: AppModel.combinedCapacity)
    /// Shown in the UI when the config file can't be read or written.
    var storageError: String?
    /// Seconds Run All waits for one stage to become ready.
    private(set) var stageTimeoutSeconds = AppConfig.defaultStageTimeout
    /// Progress of a staged Run All / Restart All; `nil` when idle.
    private(set) var startup: StartupState?
    /// Saved commands offered in Edit Service.
    private(set) var commandPresets: [String] = []
    /// Run All starts stage by stage, or everything at once.
    private(set) var startupMode = StartupMode.staged
    /// Post a macOS notification when a service dies.
    private(set) var notifyOnCrash = true

    @ObservationIgnored private let storeURL: URL
    @ObservationIgnored private let registry: RunRegistry
    @ObservationIgnored private var nextLogID = 0
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    /// Posts "service died" notifications. Activated by `AppDelegate`.
    @ObservationIgnored let notifier = CrashNotifier()

    init(storeURL: URL = ConfigStore.defaultURL, registry: RunRegistry = RunRegistry()) {
        self.storeURL = storeURL
        self.registry = registry
        registry.reapStale()
        do {
            let config = try ConfigStore.load(from: storeURL)
            runtimes = config.services.map(makeRuntime)
            stageTimeoutSeconds = config.stageTimeoutSeconds
            commandPresets = config.commandPresets
            startupMode = config.startupMode
            notifyOnCrash = config.notifyOnCrash
        } catch {
            logger.error("Config load failed: \(error.localizedDescription, privacy: .public)")
            storageError = error.localizedDescription
        }
        startStatsLoop()
    }

    var runningCount: Int { runtimes.count { $0.status.isAlive } }
    var problemCount: Int { runtimes.count(where: \.hasProblem) }
    var hasErrorCounts: Bool { runtimes.contains { $0.logs.errorCount > 0 || $0.logs.warnCount > 0 } }

    func runtime(for id: UUID) -> ServiceRuntime? {
        runtimes.first { $0.id == id }
    }

    func name(of serviceID: UUID) -> String {
        runtime(for: serviceID)?.config.name ?? "?"
    }

    // MARK: - Bulk actions

    /// Starts every service, stage by stage or all at once (see `startupMode`).
    func runAll() {
        startupTask?.cancel()
        startupTask = Task { await runStaged() }
    }

    /// Stops everything, waits until the old processes are gone (ports free), then starts again (see `startupMode`).
    func restartAll() {
        startupTask?.cancel()
        startupTask = Task {
            let alive = runtimes.filter { $0.status.isAlive }
            alive.forEach { $0.stop() }
            let deadline = ContinuousClock.now + Self.stopAllTimeout
            while alive.contains(where: { $0.status.isAlive }), ContinuousClock.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
            }
            await runStaged()
        }
    }

    func stopAll() {
        cancelStartup()
        runtimes.forEach { $0.stop() }
    }

    func cancelStartup() {
        startupTask?.cancel()
        startupTask = nil
        startup = nil
    }

    func dismissStartup() {
        if startup?.isActive != true { startup = nil }
    }

    func setStage(_ stage: Int, for id: UUID) {
        guard var config = runtime(for: id)?.config else { return }
        config.startStage = StartPlan.clamped(stage)
        update(config)
    }

    func setStageTimeout(_ seconds: Int) {
        stageTimeoutSeconds = min(max(seconds, AppConfig.stageTimeoutRange.lowerBound), AppConfig.stageTimeoutRange.upperBound)
        save()
    }
    func setStartupMode(_ mode: StartupMode) {
        guard mode != startupMode else { return }
        startupMode = mode
        save()
    }

    func setNotifyOnCrash(_ enabled: Bool) {
        guard enabled != notifyOnCrash else { return }
        notifyOnCrash = enabled
        save()
    }

    func clearCombinedLogs() { combinedLogs.clear() }

    // MARK: - Editing

    func add(_ config: ServiceConfig) {
        runtimes = runtimes + [makeRuntime(config)]
        save()
    }

    func update(_ config: ServiceConfig) {
        runtime(for: config.id)?.update(config: config)
        save()
    }

    func remove(id: UUID) {
        if let runtime = runtime(for: id), runtime.status.isAlive {
            runtime.stop()
            retiring = retiring + [runtime]
        }
        runtimes = runtimes.filter { $0.id != id }
        save()
    }

    func move(id: UUID, by offset: Int) {
        guard let index = runtimes.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard runtimes.indices.contains(target) else { return }
        var reordered = runtimes
        reordered.swapAt(index, target)
        runtimes = reordered
        save()
    }

    /// Drag-and-drop in All Services: puts `id` next to `target` and saves the new order.
    func move(id: UUID, onto target: UUID, after: Bool) {
        let order = runtimes.map(\.id).moving(id, onto: target, after: after)
        guard order != runtimes.map(\.id) else { return }
        runtimes = order.compactMap(runtime(for:))
        save()
    }

    /// Saves a tile size chosen in All Services; `nil` values go back to automatic.
    func setTileSize(id: UUID, span: Int?, height: Double?) {
        guard let runtime = runtime(for: id) else { return }
        var updated = runtime.config
        updated.tileSpan = span
        updated.tileHeight = height
        guard updated != runtime.config else { return }
        runtime.update(config: updated)
        save()
    }

    func clearAllErrorCounts() {
        runtimes.forEach { $0.clearErrorCount() }
    }

    /// Puts every tile in All Services back to its automatic size.
    func resetTileSizes() {
        runtimes.forEach { runtime in
            var updated = runtime.config
            updated.tileSpan = nil
            updated.tileHeight = nil
            if updated != runtime.config { runtime.update(config: updated) }
        }
        save()
    }

    func addCommandPreset(_ command: String) {
        let updated = CommandPresets.adding(command, to: commandPresets)
        guard updated != commandPresets else { return }
        commandPresets = updated
        save()
    }

    func removeCommandPreset(_ command: String) {
        commandPresets = CommandPresets.removing(command, from: commandPresets)
        save()
    }

    // MARK: - Export / Import

    enum ImportMode {
        /// Add new services, update same-name ones, keep the rest.
        case merge
        /// The imported file becomes the whole config.
        case replace
    }

    func exportConfig(to url: URL) throws(ConfigStoreError) {
        try ConfigStore.save(ConfigTransfer.portable(appConfig, home: NSHomeDirectory()), to: url)
    }

    /// Applies an imported config. Runtimes whose id survives keep running with the new settings;
    /// removed services are stopped.
    func applyImport(_ imported: AppConfig, mode: ImportMode) {
        let next = switch mode {
        case .merge: ConfigTransfer.merge(local: appConfig, imported: imported)
        case .replace: ConfigTransfer.replace(local: appConfig, imported: imported)
        }
        let keptIDs = Set(next.services.map(\.id))
        for runtime in runtimes where !keptIDs.contains(runtime.id) && runtime.status.isAlive {
            runtime.stop()
            retiring = retiring + [runtime]
        }
        runtimes = next.services.map { config in
            guard let existing = runtime(for: config.id) else { return makeRuntime(config) }
            existing.update(config: config)
            return existing
        }
        stageTimeoutSeconds = next.stageTimeoutSeconds
        commandPresets = next.commandPresets
        startupMode = next.startupMode
        notifyOnCrash = next.notifyOnCrash
        save()
    }

    // MARK: - Quit

    /// Sends SIGTERM to every service, waits briefly, then SIGKILLs whatever is left.
    func shutdownAll(timeout: TimeInterval = 3) {
        statsTask?.cancel()
        let runners = (runtimes + retiring).compactMap { $0.terminateForQuit() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, runners.contains(where: \.isGroupAlive) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        runners.filter(\.isGroupAlive).forEach { $0.forceKill() }
    }

    // MARK: - Private

    private func runStaged() async {
        let stages = StartPlan.stages(runtimes.map { (id: $0.id, stage: $0.config.startStage) }, mode: startupMode)
        let alreadyUp = Set(runtimes.filter { $0.status.isAlive }.map(\.id))
        var notes: [String] = []
        defer { if Task.isCancelled { startup = nil } }

        for (index, ids) in stages.enumerated() {
            if Task.isCancelled { return }
            let group = ids.compactMap(runtime(for:))
            group.forEach { $0.start() }
            guard index < stages.count - 1 else { break }

            let began = ContinuousClock.now
            waiting: while true {
                let signals = Dictionary(uniqueKeysWithValues: group.map { ($0.id, $0.startSignal(wasAlreadyUp: alreadyUp.contains($0.id))) })
                let elapsed = began.duration(to: .now).seconds
                switch StageGate.evaluate(signals: signals, elapsed: elapsed, timeout: Double(stageTimeoutSeconds)) {
                case .ready:
                    break waiting
                case .failed(let failedIDs):
                    let names = failedIDs.map(name(of:)).joined(separator: ", ")
                    startup = StartupState(stage: index + 1, totalStages: stages.count, waitingFor: [], isActive: false,
                                           notes: notes + ["Stage \(index + 1) failed (\(names)) — later stages were not started."])
                    return
                case .timedOut(let pendingIDs):
                    notes.append("Stage \(index + 1): \(pendingIDs.map(name(of:)).joined(separator: ", ")) not ready after \(stageTimeoutSeconds)s — continued anyway.")
                    break waiting
                case .waiting:
                    startup = StartupState(stage: index + 1, totalStages: stages.count,
                                           waitingFor: signals.filter { $0.value == .pending }.keys.map(name(of:)).sorted(),
                                           isActive: true, notes: notes)
                    try? await Task.sleep(for: Self.pollInterval)
                    if Task.isCancelled { return }
                }
            }
        }
        startup = notes.isEmpty ? nil : StartupState(stage: stages.count, totalStages: stages.count, waitingFor: [],
                                                     isActive: false, notes: notes)
    }

    private func makeRuntime(_ config: ServiceConfig) -> ServiceRuntime {
        let runtime = ServiceRuntime(
            config: config, registry: registry,
            protectedGroups: { [weak self] in Set(self?.runtimes.compactMap(\.processGroup) ?? []) },
            onConfigChange: { [weak self] in self?.save() }
        ) { [weak self] runtime, texts, level in
            self?.emit(from: runtime, texts: texts, level: level) ?? []
        }
        runtime.onCrash = { [weak self] runtime, event in self?.report(event, from: runtime) }
        return runtime
    }

    private func report(_ event: CrashEvent, from runtime: ServiceRuntime) {
        guard notifyOnCrash else { return }
        let body = switch event {
        case .crashed(let code) where code < 0: "Crashed (signal \(-code))"
        case .crashed(let code): "Crashed (exit \(code))"
        case .gaveUp(let attempts): "Gave up after \(attempts) restarts"
        }
        notifier.post(serviceID: runtime.id, title: runtime.config.name, body: body)
    }

    private func emit(from runtime: ServiceRuntime, texts: [String], level: LogLevel?) -> [LogLine] {
        let now = Date()
        let lines = texts.map { text in
            nextLogID += 1
            return LogLine(id: nextLogID, serviceID: runtime.id, date: now, text: text,
                           level: level ?? LogClassifier.level(of: text))
        }
        combinedLogs.append(lines)
        return lines
    }

    /// Everything written to `services.json` (and to an exported file).
    private var appConfig: AppConfig {
        AppConfig(services: runtimes.map(\.config), stageTimeoutSeconds: stageTimeoutSeconds,
                  commandPresets: commandPresets, startupMode: startupMode, notifyOnCrash: notifyOnCrash)
    }

    private func save() {
        do {
            try ConfigStore.save(appConfig, to: storeURL)
            storageError = nil
        } catch {
            logger.error("Config save failed: \(error.localizedDescription, privacy: .public)")
            storageError = error.localizedDescription
        }
    }

    private func startStatsLoop() {
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.statsInterval)
                guard let self else { return }
                self.retiring = self.retiring.filter(\.status.isAlive)
                guard self.runtimes.contains(where: { $0.status.isAlive }) else { continue }
                let stats = await StatsSampler.sample()
                let now = Date()
                self.runtimes.forEach { $0.refresh(stats: stats, now: now) }
            }
        }
    }
}

/// What the panel shows while services start stage by stage.
struct StartupState: Equatable {
    let stage: Int
    let totalStages: Int
    let waitingFor: [String]
    /// `false` once finished with notes (timeouts) or aborted by a failure.
    let isActive: Bool
    let notes: [String]
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
