import Foundation

/// Moving a config between Macs: export-friendly paths, re-rooting folders, and merging into the local config.
public enum ConfigTransfer {
    /// Services are matched across machines by name, ignoring case and surrounding spaces.
    public static func sameName(_ a: String, _ b: String) -> Bool {
        key(a) == key(b)
    }

    /// The deepest folder every path lives in, compared by whole folder names. For one path, its parent.
    /// `nil` when there are no paths or they share nothing but `/`.
    public static func commonRoot(of paths: [String]) -> String? {
        guard let first = paths.first else { return nil }
        var shared = components(first)
        if paths.count == 1 { shared = Array(shared.dropLast()) }
        for path in paths.dropFirst() {
            shared = zip(shared, components(path)).prefix { $0.0 == $0.1 }.map { $0.0 }
        }
        guard shared.contains(where: { !$0.isEmpty }) else { return nil }
        return shared.joined(separator: "/")
    }

    /// Replaces `oldRoot` at the start of `path` with `newRoot`. Paths outside `oldRoot` are returned unchanged.
    public static func remap(_ path: String, from oldRoot: String, to newRoot: String, home: String) -> String {
        let parts = components(path)
        let root = components(oldRoot)
        guard parts.count >= root.count, Array(parts.prefix(root.count)) == root else { return path }
        var base = newRoot
        while base.count > 1, base.hasSuffix("/") { base.removeLast() }
        let joined = ([base] + parts.dropFirst(root.count)).joined(separator: "/")
        return ServiceConfig.abbreviate(joined, home: home)
    }

    public static func remapping(_ config: AppConfig, from oldRoot: String, to newRoot: String,
                                 home: String) -> AppConfig {
        var copy = config
        copy.services = config.services.map { service in
            var moved = service
            moved.path = remap(service.path, from: oldRoot, to: newRoot, home: home)
            return moved
        }
        return copy
    }

    /// Paths under `home` written as `~/…`, so they still work for a different user name.
    public static func portable(_ config: AppConfig, home: String) -> AppConfig {
        var copy = config
        copy.services = config.services.map { service in
            var portable = service
            portable.path = ServiceConfig.abbreviate(service.expandedPath(home: home), home: home)
            return portable
        }
        return copy
    }

    /// Updates same-name services (keeping their local id), appends new ones, keeps local-only ones,
    /// unions the presets, and keeps the local startup settings.
    public static func merge(local: AppConfig, imported: AppConfig) -> AppConfig {
        var result = local
        for incoming in imported.services {
            if let index = result.services.firstIndex(where: { sameName($0.name, incoming.name) }) {
                var updated = incoming
                updated.id = result.services[index].id
                result.services[index] = updated
            } else {
                var added = incoming
                added.id = UUID()
                result.services.append(added)
            }
        }
        for preset in imported.commandPresets where !result.commandPresets.contains(preset) {
            result.commandPresets.append(preset)
        }
        return result
    }

    /// The imported config becomes the whole config. Same-name services keep their local id
    /// (so a running service stays attached to its process); every other service gets a fresh id.
    public static func replace(local: AppConfig, imported: AppConfig) -> AppConfig {
        var unclaimed = local.services
        var result = imported
        result.services = imported.services.map { incoming in
            var service = incoming
            if let index = unclaimed.firstIndex(where: { sameName($0.name, incoming.name) }) {
                service.id = unclaimed.remove(at: index).id
            } else {
                service.id = UUID()
            }
            return service
        }
        return result
    }

    private static func key(_ name: String) -> String {
        name.trimmed.lowercased()
    }

    /// `"/a/b/"` → `["", "a", "b"]`, `"~/a"` → `["~", "a"]`.
    private static func components(_ path: String) -> [String] {
        var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        while parts.count > 1, parts.last == "" { parts.removeLast() }
        return parts
    }
}
