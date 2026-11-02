import Foundation

/// Decides whether a crashed service is started again, and after how long.
/// A service that stayed running for `stableAfter` seconds gets a fresh set of attempts.
public struct RestartPolicy: Equatable, Sendable {
    /// Wait before each automatic restart; its count is the maximum number of attempts.
    public static let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(10)]
    public static let stableAfter: TimeInterval = 60

    public enum Decision: Equatable, Sendable {
        case restart(after: Duration, attempt: Int)
        case giveUp
    }

    public private(set) var attempts = 0
    private var runningSince: Date?

    public init() {}

    public mutating func becameRunning(at date: Date) {
        runningSince = date
    }

    public mutating func crashed(at date: Date) -> Decision {
        if let runningSince, date.timeIntervalSince(runningSince) >= Self.stableAfter { attempts = 0 }
        runningSince = nil
        guard attempts < Self.delays.count else { return .giveUp }
        attempts += 1
        return .restart(after: Self.delays[attempts - 1], attempt: attempts)
    }

    public mutating func reset() {
        attempts = 0
        runningSince = nil
    }
}
