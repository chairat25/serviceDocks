import Foundation

/// Decides when a starting service has become ready.
public enum Readiness {
    /// Still alive this long after launch without a ready line → treat as running.
    public static let gracePeriod: Double = 10

    /// One-off convenience; the app keeps a `ReadyMatcher` per service so a custom regex compiles once.
    public static func isReady(_ line: String, customPattern: String?) -> Bool {
        ReadyMatcher(customPattern: customPattern).isReady(line)
    }
}

/// Matches "the service is ready" lines. It runs on every log line until a ready line shows up
/// (forever for services without a recognisable one), so the built-in patterns are guarded by a
/// cheap byte search and the regex only runs on lines that could match.
public final class ReadyMatcher: @unchecked Sendable {
    nonisolated(unsafe) private static let defaultPattern = #/
        (?i)
        running \s+ (on|at) \s+ https?:\/\/
        | successfully \s+ started
        | ready \s+ in \s+ \d
        | compiled \s+ successfully
        | listening \s+ (on|at)
        | local: \s+ https?:\/\/
        | server \s+ (is \s+)? (started|running|listening)
        | started \s+ server \s+ on
        | swagger \s+ documentation \s+ available
    /#

    /// Every built-in pattern contains one of these (lowercase) words.
    private static let stems: [StaticString] = ["running", "started", "ready", "compiled", "listening", "local:", "server", "swagger"]

    private let custom: Regex<AnyRegexOutput>?

    /// An empty or invalid pattern falls back to the built-in ones.
    public init(customPattern: String?) {
        if let customPattern, !customPattern.isEmpty {
            custom = try? Regex(customPattern)
        } else {
            custom = nil
        }
    }

    public func isReady(_ line: String) -> Bool {
        if let custom { return line.contains(custom) }
        guard Self.mightMatch(line) else { return false }
        return line.contains(Self.defaultPattern)
    }

    private static func mightMatch(_ line: String) -> Bool {
        var lowered = Array(line.utf8)
        for index in lowered.indices where (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(lowered[index]) {
            lowered[index] |= 0x20
        }
        return lowered.withUnsafeBufferPointer { buffer in
            stems.contains { stem in
                memmem(buffer.baseAddress, buffer.count, stem.utf8Start, stem.utf8CodeUnitCount) != nil
            }
        }
    }
}
