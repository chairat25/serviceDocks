/// Lifecycle of a service process.
public enum ServiceStatus: Equatable, Sendable {
    case stopped
    /// Process is alive but has not printed a "ready" line yet.
    case starting
    case running
    /// Stop was requested; waiting for the process group to exit.
    case stopping
    /// Process exited without being asked to. Negative codes are signals.
    case down(exitCode: Int32)

    /// The process group exists.
    public var isAlive: Bool {
        switch self {
        case .starting, .running, .stopping: true
        case .stopped, .down: false
        }
    }

    public var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .down(let code) where code < 0: "Down (signal \(-code))"
        case .down(let code): "Down (exit \(code))"
        }
    }
}
