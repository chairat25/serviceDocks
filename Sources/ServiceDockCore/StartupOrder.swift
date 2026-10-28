import Foundation

/// Groups services into start-up stages. Stage 1 starts first; each later stage starts
/// only after the previous one is ready (e.g. a service that must finish compiling first).
public enum StartPlan {
    public static let stageRange = 1...20

    public static func clamped(_ stage: Int) -> Int {
        min(max(stage, stageRange.lowerBound), stageRange.upperBound)
    }

    /// Lowest stage first; inside a stage the original list order is kept.
    public static func stages(_ items: [(id: UUID, stage: Int)]) -> [[UUID]] {
        let grouped = Dictionary(grouping: items, by: { $0.stage })
        return grouped.keys.sorted().map { stage in grouped[stage, default: []].map(\.id) }
    }
}

/// Decides whether the next stage may start.
public enum StageGate {
    public enum Signal: Equatable, Sendable {
        case pending
        /// The service printed its "ready" line.
        case ready
        /// The service exited or could not start.
        case failed
    }

    public enum Outcome: Equatable, Sendable {
        case waiting
        case ready
        case failed([UUID])
        /// Not ready in time: the services still pending.
        case timedOut([UUID])
    }

    public static func evaluate(signals: [UUID: Signal], elapsed: TimeInterval, timeout: TimeInterval) -> Outcome {
        let failed = signals.filter { $0.value == .failed }.keys.sorted { $0.uuidString < $1.uuidString }
        if !failed.isEmpty { return .failed(failed) }
        let pending = signals.filter { $0.value == .pending }.keys.sorted { $0.uuidString < $1.uuidString }
        if pending.isEmpty { return .ready }
        return elapsed >= timeout ? .timedOut(pending) : .waiting
    }
}
