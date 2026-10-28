/// Parses `ps -A -o pgid=,pcpu=,rss=` and aggregates per process group,
/// so a service's CPU/RAM includes yarn, node and every child it spawned.
public enum ProcessStats {
    public static let psArguments = ["-A", "-o", "pgid=,pcpu=,rss="]
    public static let historyLimit = 30

    public struct Sample: Equatable, Sendable {
        public let cpu: Double
        public let memoryKB: Int

        public init(cpu: Double, memoryKB: Int) {
            self.cpu = cpu
            self.memoryKB = memoryKB
        }
    }

    public static func parse(_ output: String) -> [Int32: Sample] {
        output.split(whereSeparator: \.isNewline).reduce(into: [:]) { result, row in
            let fields = row.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pgid = Int32(fields[0]), let cpu = Double(fields[1]),
                  let rss = Int(fields[2]) else { return }
            let previous = result[pgid] ?? Sample(cpu: 0, memoryKB: 0)
            result[pgid] = Sample(cpu: previous.cpu + cpu, memoryKB: previous.memoryKB + rss)
        }
    }

    public static func formatMemory(kb: Int) -> String {
        switch kb {
        case ..<1024: "\(kb) KB"
        case ..<(1024 * 1024): "\(kb / 1024) MB"
        default: String(format: "%.1f GB", Double(kb) / 1024 / 1024)
        }
    }

    public static func appending(_ value: Double, to history: [Double], limit: Int = historyLimit) -> [Double] {
        Array((history + [value]).suffix(limit))
    }
}
