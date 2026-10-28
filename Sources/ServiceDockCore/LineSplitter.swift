import Foundation

/// Turns raw pipe chunks into lines. Splits on bytes so a UTF-8 character
/// cut across two reads is decoded only once the whole line has arrived.
public struct LineSplitter: Sendable {
    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    /// A line without a newline is emitted anyway once it grows this large.
    public static let maxPendingBytes = 64 * 1024

    public let pending: [UInt8]

    public init(pending: [UInt8] = []) {
        self.pending = pending
    }

    public func feeding(_ chunk: Data) -> (LineSplitter, [String]) {
        let bytes = pending + chunk
        var lines: [String] = []
        var start = 0
        for (index, byte) in bytes.enumerated() where byte == Self.newline {
            lines.append(Self.decode(bytes[start..<index]))
            start = index + 1
        }
        let rest = Array(bytes[start...])
        if rest.count > Self.maxPendingBytes {
            return (LineSplitter(), lines + [Self.decode(rest[...])])
        }
        return (LineSplitter(pending: rest), lines)
    }

    /// Call on EOF to get a final line that had no trailing newline.
    public func flushed() -> [String] {
        pending.isEmpty ? [] : [Self.decode(pending[...])]
    }

    private static func decode(_ slice: ArraySlice<UInt8>) -> String {
        let trimmed = slice.last == carriageReturn ? slice.dropLast() : slice
        return String(decoding: trimmed, as: UTF8.self)
    }
}
