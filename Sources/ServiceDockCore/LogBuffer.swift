/// Bounded log history plus running error/warn counters.
public struct LogBuffer: Sendable {
    public static let defaultCapacity = 3000

    public let capacity: Int
    public private(set) var lines: [LogLine] = []
    /// Counted since the last clear, including lines already dropped by the capacity limit.
    public private(set) var errorCount = 0
    public private(set) var warnCount = 0

    public init(capacity: Int = LogBuffer.defaultCapacity) {
        self.capacity = capacity
    }

    public mutating func append(_ newLines: [LogLine]) {
        guard !newLines.isEmpty else { return }
        lines.append(contentsOf: newLines)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        errorCount += newLines.count { $0.level == .error }
        warnCount += newLines.count { $0.level == .warn }
    }

    public mutating func clear() {
        lines = []
        errorCount = 0
        warnCount = 0
    }
}
