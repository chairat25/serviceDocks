import Foundation

/// One service the user registered: where it lives and how to start it.
public struct ServiceConfig: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Folder the command runs in. May start with `~`.
    public var path: String
    /// Shell command, e.g. `yarn start:dev`.
    public var command: String
    /// Optional address shown in the UI and opened from it, e.g. `http://localhost:3001`.
    public var url: String?
    /// SF Symbol name.
    public var icon: String
    /// Regex that marks the service as ready. `nil` uses the built-in dev-server patterns.
    public var readyPattern: String?
    /// Start-up stage for Run All: lower stages start first (see `StartPlan`).
    public var startStage: Int
    /// Stop whatever still holds this service's ports before it starts (a leftover from a previous run).
    public var freesPortsOnStart: Bool
    /// Ports typed in by the user.
    public var ports: [Int]
    /// Ports this service was seen listening on; remembered automatically.
    public var learnedPorts: [Int]
    /// Width in grid columns in All Services; `nil` = one column.
    public var tileSpan: Int?
    /// Tile height in points in All Services; `nil` = fit the window.
    public var tileHeight: Double?

    public init(id: UUID = UUID(), name: String, path: String, command: String, url: String? = nil,
                icon: String? = nil, readyPattern: String? = nil, startStage: Int = 1,
                freesPortsOnStart: Bool = true, ports: [Int] = [], learnedPorts: [Int] = []) {
        self.id = id
        self.name = name
        self.path = path
        self.command = command
        self.url = url
        self.icon = icon ?? Self.suggestedIcon(for: name)
        self.readyPattern = readyPattern
        self.startStage = startStage
        self.freesPortsOnStart = freesPortsOnStart
        self.ports = ports
        self.learnedPorts = learnedPorts
    }

    /// Config files written before `startStage` existed load with stage 1.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        command = try container.decode(String.self, forKey: .command)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        icon = try container.decode(String.self, forKey: .icon)
        readyPattern = try container.decodeIfPresent(String.self, forKey: .readyPattern)
        startStage = StartPlan.clamped(try container.decodeIfPresent(Int.self, forKey: .startStage) ?? 1)
        freesPortsOnStart = try container.decodeIfPresent(Bool.self, forKey: .freesPortsOnStart) ?? true
        ports = try container.decodeIfPresent([Int].self, forKey: .ports) ?? []
        learnedPorts = try container.decodeIfPresent([Int].self, forKey: .learnedPorts) ?? []
        tileSpan = try container.decodeIfPresent(Int.self, forKey: .tileSpan)
        tileHeight = try container.decodeIfPresent(Double.self, forKey: .tileHeight)
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case emptyName
        case emptyPath
        case emptyCommand
        case directoryNotFound(String)
        case invalidURL

        public var message: String {
            switch self {
            case .emptyName: "Name is required."
            case .emptyPath: "Folder is required."
            case .emptyCommand: "Command is required."
            case .directoryNotFound(let path): "Folder not found: \(path)"
            case .invalidURL: "URL must start with http:// or https://"
            }
        }
    }

    /// Every port to clear before starting: typed, learned, and the one in the URL.
    public var portsToFree: [Int] {
        guard freesPortsOnStart else { return [] }
        let urlPort = url.flatMap { URL(string: $0.trimmed)?.port }
        return Set(ports + learnedPorts + [urlPort].compactMap { $0 })
            .filter { PortList.validRange.contains($0) }
            .sorted()
    }

    public func expandedPath(home: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return home + path.dropFirst()
    }

    public static func abbreviate(_ path: String, home: String) -> String {
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public func validate(home: String, directoryExists: (String) -> Bool) -> [ValidationError] {
        var errors: [ValidationError] = []
        if name.trimmed.isEmpty { errors.append(.emptyName) }
        if path.trimmed.isEmpty {
            errors.append(.emptyPath)
        } else if !directoryExists(expandedPath(home: home)) {
            errors.append(.directoryNotFound(expandedPath(home: home)))
        }
        if command.trimmed.isEmpty { errors.append(.emptyCommand) }
        if let url, !url.trimmed.isEmpty, !Self.isWebURL(url.trimmed) { errors.append(.invalidURL) }
        return errors
    }

    private static func isWebURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Keyword → symbol, checked in order; the first keyword contained in the name wins.
    private static let iconRules: [(keywords: [String], icon: String)] = [
        (["auth", "login", "identity"], "shield.lefthalf.filled"),
        (["profile", "user", "account"], "person.fill"),
        (["transaction", "payment", "billing"], "creditcard.fill"),
        (["data", "db", "store"], "cylinder.split.1x2.fill"),
        (["web", "front", "ui", "client"], "desktopcomputer"),
        (["gateway", "proxy", "bff"], "point.3.connected.trianglepath.dotted"),
        (["worker", "job", "queue", "cron"], "gearshape.fill"),
        (["notif", "mail", "sms"], "bell.fill"),
        (["report", "analytic"], "chart.bar.fill")
    ]

    public static let defaultIcon = "server.rack"

    public static let iconChoices: [String] = iconRules.map(\.icon) + [
        defaultIcon, "shippingbox.fill", "bolt.fill", "cart.fill", "globe", "terminal.fill", "lock.fill", "cpu"
    ]

    public static func suggestedIcon(for name: String) -> String {
        let lowered = name.lowercased()
        return iconRules.first { rule in rule.keywords.contains { lowered.contains($0) } }?.icon ?? defaultIcon
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
