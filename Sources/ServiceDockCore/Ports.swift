import Foundation

public enum PortList {
    public static let validRange = 1...65535

    /// "8000, 50055" → [8000, 50055]. Junk, out-of-range numbers and duplicates are dropped.
    public static func parse(_ text: String) -> [Int] {
        var seen = Set<Int>()
        return text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .compactMap { Int($0) }
            .filter { validRange.contains($0) && seen.insert($0).inserted }
    }

    public static func format(_ ports: [Int]) -> String {
        ports.map(String.init).joined(separator: ", ")
    }

    /// Adds newly seen ports to the remembered ones, sorted, never growing past `limit`.
    public static func merge(_ known: [Int], with found: [Int], limit: Int = 12) -> [Int] {
        let combined = Set(known).union(found.filter { validRange.contains($0) })
        guard combined.count <= limit else { return known }
        return combined.sorted()
    }
}

/// Parsers for `lsof` output.
public enum LsofParser {
    /// `lsof -Fn` lines look like `n*:8000`, `n127.0.0.1:3001`, `n[::1]:50055`.
    public static func listeningPorts(fromFn output: String) -> [Int] {
        let ports = output.split(whereSeparator: \.isNewline).compactMap { line -> Int? in
            guard line.hasPrefix("n"), let colon = line.lastIndex(of: ":") else { return nil }
            return Int(line[line.index(after: colon)...])
        }
        return Array(Set(ports.filter { PortList.validRange.contains($0) })).sorted()
    }

    /// `lsof -Fpn` prints `p<pid>` followed by that process's `n<address>` lines.
    /// Returns, per pid, which of the `wanted` ports it listens on.
    public static func portsByPid(fromFpn output: String, wanted: Set<Int>) -> [Int32: [Int]] {
        var result: [Int32: [Int]] = [:]
        var current: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                current = pid
            } else if let pid = current, let port = listeningPorts(fromFn: String(line)).first, wanted.contains(port) {
                result[pid] = Array(Set(result[pid, default: []] + [port])).sorted()
            }
        }
        return result
    }
}
