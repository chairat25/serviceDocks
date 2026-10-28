import Foundation

/// Detects `.env*` edits made after a service started, so the UI can suggest a restart.
public enum EnvWatch {
    public typealias Snapshot = [String: Date]

    private static let ignoredSuffixes = [".example", ".sample", ".template"]

    public static func isEnvFile(_ name: String) -> Bool {
        guard name == ".env" || name.hasPrefix(".env.") else { return false }
        return !ignoredSuffixes.contains { name.hasSuffix($0) }
    }

    /// Modification dates of the env files directly inside `directory`.
    public static func snapshot(of directory: String, fileManager: FileManager = .default) -> Snapshot {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
        return names.filter(isEnvFile).reduce(into: [:]) { result, name in
            let attributes = try? fileManager.attributesOfItem(atPath: (directory as NSString).appendingPathComponent(name))
            result[name] = attributes?[.modificationDate] as? Date
        }
    }

    /// Files that were modified, added or removed between two snapshots, sorted by name.
    public static func changedFiles(from old: Snapshot, to new: Snapshot) -> [String] {
        Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.sorted()
    }
}
