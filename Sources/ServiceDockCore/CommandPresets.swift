import Foundation

/// Saved commands offered in Edit Service so the same command does not have to be typed again.
public enum CommandPresets {
    public static func adding(_ command: String, to presets: [String]) -> [String] {
        let cleaned = command.trimmed
        guard !cleaned.isEmpty, !presets.contains(cleaned) else { return presets }
        return presets + [cleaned]
    }

    public static func removing(_ command: String, from presets: [String]) -> [String] {
        presets.filter { $0 != command }
    }

    /// Commands other services already use that are not saved as presets (first-seen order, no repeats).
    public static func usedElsewhere(serviceCommands: [String], presets: [String]) -> [String] {
        serviceCommands.map(\.trimmed).reduce(into: [String]()) { result, command in
            guard !command.isEmpty, !presets.contains(command), !result.contains(command) else { return }
            result.append(command)
        }
    }
}
