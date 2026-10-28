import Foundation

public enum LogLevel: String, Sendable, CaseIterable {
    case debug, info, warn, error
}

public struct LogLine: Identifiable, Equatable, Sendable {
    /// Monotonic sequence number; unique across all services.
    public let id: Int
    public let serviceID: UUID
    public let date: Date
    public let text: String
    public let level: LogLevel

    public init(id: Int, serviceID: UUID, date: Date, text: String, level: LogLevel) {
        self.id = id
        self.serviceID = serviceID
        self.date = date
        self.text = text
        self.level = level
    }
}

public enum LogClassifier {
    nonisolated(unsafe) private static let ansi = /\u{1B}(?:\[[0-9;?]*[ -\/]*[@-~]|\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\)|[@-Z\\-_])/

    private static let escape: UInt8 = 0x1B
    private static let carriageReturn: UInt8 = 0x0D

    /// Removes ANSI escapes and keeps only what a terminal would show after `\r` overwrites.
    /// Most lines contain neither, so they skip the regex entirely.
    public static func clean(_ raw: String) -> String {
        guard raw.utf8.contains(where: { $0 == escape || $0 == carriageReturn }) else { return raw }
        let visible = raw.split(separator: "\r", omittingEmptySubsequences: false).last.map(String.init) ?? raw
        return visible.replacing(ansi, with: "")
    }

    /// Keeps a runaway line (minified JSON, a huge stack dump) from eating memory.
    public static func clamp(_ line: String, limit: Int) -> String {
        // utf8.count is O(1) for native strings; only long lines pay for the grapheme count.
        guard line.utf8.count > limit, line.count > limit else { return line }
        return String(line.prefix(limit)) + "… (+\(line.count - limit) chars)"
    }

    /// True when the line has something other than spaces and tabs.
    public static func hasContent(_ line: String) -> Bool {
        line.utf8.contains { $0 != 0x20 && $0 != 0x09 }
    }

    /// Error > warn > debug > info, decided by whole words (case-insensitive), e.g. `ERROR`, `Warning`,
    /// `npm ERR!`, `ECONNREFUSED`, `Unhandled…`. "errors" or "0 errors found" stay info.
    /// A single byte scan: this runs on every log line, so it avoids regex.
    public static func level(of line: String) -> LogLevel {
        if line.hasPrefix(nestPrefix), let level = nestLevel(of: line) { return level }
        var copy = line
        return copy.withUTF8 { classify($0) }
    }

    private static let nestPrefix = "[Nest]"
    private static let nestLevels: [Substring: LogLevel] = [
        "LOG": .info, "ERROR": .error, "FATAL": .error, "WARN": .warn, "DEBUG": .debug, "VERBOSE": .debug
    ]

    /// NestJS prints `[Nest] pid  - date   LEVEL [Context] message`; the level column is authoritative,
    /// so words inside the message (e.g. "log levels: …, error") don't change it.
    private static func nestLevel(of line: String) -> LogLevel? {
        guard let contextStart = line.firstIndex(of: "[", after: line.index(line.startIndex, offsetBy: nestPrefix.count)) else {
            return nil
        }
        let header = line[..<contextStart]
        return header.split(separator: " ").last.flatMap { nestLevels[$0] }
    }

    private static let maxKeywordLength = 16

    private static func classify(_ bytes: UnsafeBufferPointer<UInt8>) -> LogLevel {
        var level = LogLevel.info
        var index = 0
        let count = bytes.count
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: maxKeywordLength) { word in
            while index < count {
                guard isWordByte(bytes[index]) else {
                    index += 1
                    continue
                }
                var length = 0
                while index < count, isWordByte(bytes[index]) {
                    if length < maxKeywordLength { word[length] = lowercased(bytes[index]) }
                    length += 1
                    index += 1
                }
                let isFollowedByBang = index < count && bytes[index] == UInt8(ascii: "!")
                let token = UnsafeBufferPointer(start: word.baseAddress, count: min(length, maxKeywordLength))
                let found = levelOf(token: token, fullLength: length, followedByBang: isFollowedByBang)
                if found == .error { level = .error; return }
                if found == .warn || (found == .debug && level == .info) { level = found ?? level }
            }
        }
        return level
    }

    private static func levelOf(token: UnsafeBufferPointer<UInt8>, fullLength: Int, followedByBang: Bool) -> LogLevel? {
        // Longer than any keyword except the "unhandled…" prefix family.
        if fullLength >= 9, hasPrefix(token, "unhandled") { return .error }
        guard fullLength <= maxKeywordLength else { return nil }
        if equals(token, "error") || equals(token, "fatal") || equals(token, "exception") || equals(token, "panic")
            || equals(token, "econnrefused") || equals(token, "eaddrinuse") || (equals(token, "err") && followedByBang) {
            return .error
        }
        if equals(token, "warn") || equals(token, "warning") || equals(token, "deprecated") { return .warn }
        if equals(token, "debug") || equals(token, "verbose") || equals(token, "trace") { return .debug }
        return nil
    }

    /// Letters, digits, underscore, and any non-ASCII byte count as part of a word.
    private static func isWordByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), 0x80...:
            true
        default:
            false
        }
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte | 0x20 : byte
    }

    private static func equals(_ token: UnsafeBufferPointer<UInt8>, _ word: StaticString) -> Bool {
        token.count == word.utf8CodeUnitCount && memcmp(token.baseAddress, word.utf8Start, token.count) == 0
    }

    private static func hasPrefix(_ token: UnsafeBufferPointer<UInt8>, _ word: StaticString) -> Bool {
        token.count >= word.utf8CodeUnitCount && memcmp(token.baseAddress, word.utf8Start, word.utf8CodeUnitCount) == 0
    }
}

private extension String {
    func firstIndex(of character: Character, after start: Index) -> Index? {
        self[start...].firstIndex(of: character)
    }
}
