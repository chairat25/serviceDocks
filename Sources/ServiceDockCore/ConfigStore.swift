import Foundation

/// Everything persisted to disk.
public struct AppConfig: Codable, Equatable, Sendable {
    public static let defaultStageTimeout = 90
    public static let stageTimeoutRange = 10...600

    public var services: [ServiceConfig]
    /// How long Run All waits for one stage to become ready before moving on anyway.
    public var stageTimeoutSeconds: Int
    /// Saved commands offered in Edit Service.
    public var commandPresets: [String]

    public init(services: [ServiceConfig] = [], stageTimeoutSeconds: Int = AppConfig.defaultStageTimeout,
                commandPresets: [String] = []) {
        self.services = services
        self.stageTimeoutSeconds = stageTimeoutSeconds
        self.commandPresets = commandPresets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        services = try container.decode([ServiceConfig].self, forKey: .services)
        let timeout = try container.decodeIfPresent(Int.self, forKey: .stageTimeoutSeconds) ?? Self.defaultStageTimeout
        commandPresets = try container.decodeIfPresent([String].self, forKey: .commandPresets) ?? []
        stageTimeoutSeconds = min(max(timeout, Self.stageTimeoutRange.lowerBound), Self.stageTimeoutRange.upperBound)
    }
}

public enum ConfigStoreError: Error, LocalizedError {
    case unreadable(URL, underlying: String)
    case unwritable(URL, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url, let reason): "Could not read \(url.path): \(reason)"
        case .unwritable(let url, let reason): "Could not save \(url.path): \(reason)"
        }
    }
}

public enum ConfigStore {
    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("ServiceDock", isDirectory: true)
            .appendingPathComponent("services.json")
    }

    /// A missing file is a fresh install and yields an empty config.
    public static func load(from url: URL) throws(ConfigStoreError) -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
        } catch {
            throw .unreadable(url, underlying: error.localizedDescription)
        }
    }

    public static func save(_ config: AppConfig, to url: URL) throws(ConfigStoreError) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url, options: .atomic)
        } catch {
            throw .unwritable(url, underlying: error.localizedDescription)
        }
    }
}
