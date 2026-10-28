import Foundation

/// A process group ServiceDock started. Saved to disk so a later launch can clean up
/// groups left behind when the app was killed or crashed.
public struct RunRecord: Codable, Equatable, Sendable {
    public let pgid: Int32
    /// `ps -o lstart=` of the group leader — guards against pid reuse.
    public let startTime: String
    public let name: String

    public init(pgid: Int32, startTime: String, name: String) {
        self.pgid = pgid
        self.startTime = startTime
        self.name = name
    }
}

public enum StaleProcess {
    /// Kill only when the pid still belongs to the same process we started.
    public static func isSame(_ record: RunRecord, currentStartTime: String?) -> Bool {
        currentStartTime == record.startTime
    }

    public static func startTime(fromPS output: String) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
