# Config Transfer, Parallel Start, Auto-Restart, Crash Notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users export/import their ServiceDock config between Macs, start all services in parallel, auto-restart crashed services, and get a macOS notification when a service dies.

**Architecture:** All decision logic (config merge/replace/remap, restart back-off, stage planning) lives in the pure `ServiceDockCore` target and is unit tested with swift-testing. The `ServiceDock` app target wires that logic into `AppModel`, `ServiceRuntime` and SwiftUI pages; app-target changes are verified by `swift build` plus a manual check in the built app.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, swift-testing, UserNotifications. macOS 15+.

**Spec:** `docs/superpowers/specs/2026-11-02-config-transfer-parallel-autorestart-design.md`

## Global Constraints

- Platform: macOS 15+, Swift tools 6.0, no third-party dependencies.
- Every new persisted field decodes with a default when missing: `startupMode` → `staged`, `notifyOnCrash` → `true`, `autoRestart` → `false`.
- Restart back-off: 2 s, 5 s, 10 s; max 3 attempts; counter resets after 60 s continuously running.
- Export default file name: `servicedock-config.json`. Exported service paths under home are written as `~/…`.
- Merge/replace match services by name, case-insensitive and trimmed. Matched services keep the local `id`.
- Notifications are skipped when the app is not running from a `.app` bundle (`swift run`).
- Commands: build `swift build`, test `swift test`, app bundle `scripts/build-app.sh`. Run all from the repo root.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## File Map

| File | Change | Responsibility |
|---|---|---|
| `Sources/ServiceDockCore/ConfigStore.swift` | modify | `AppConfig.startupMode`, `AppConfig.notifyOnCrash` |
| `Sources/ServiceDockCore/ServiceConfig.swift` | modify | `ServiceConfig.autoRestart` |
| `Sources/ServiceDockCore/StartupOrder.swift` | modify | `StartupMode` enum, `StartPlan.stages(_:mode:)` |
| `Sources/ServiceDockCore/RestartPolicy.swift` | create | back-off / give-up decisions |
| `Sources/ServiceDockCore/ConfigTransfer.swift` | create | common root, remap, portable, merge, replace |
| `Sources/ServiceDock/AppModel.swift` | modify | startup mode, notify setting, crash reports, export/import |
| `Sources/ServiceDock/Runtime/ServiceRuntime.swift` | modify | auto-restart, `CrashEvent`, `onCrash` |
| `Sources/ServiceDock/Runtime/CrashNotifier.swift` | create | `UNUserNotificationCenter` wrapper |
| `Sources/ServiceDock/Views/LogWindowPresenter.swift` | create | opens a service log window from AppKit (notification click) |
| `Sources/ServiceDock/Views/ImportPage.swift` | create | Import page (summary, root remap, Merge/Replace) |
| `Sources/ServiceDock/Views/StartupOrderPage.swift` | modify | Staged / Parallel switch |
| `Sources/ServiceDock/Views/ServiceEditorView.swift` | modify | "Restart if it crashes" toggle |
| `Sources/ServiceDock/Views/MenuBarPanel.swift` | modify | Export/Import/Notify menu items, import route |
| `Sources/ServiceDock/ServiceDockApp.swift` | modify | activate notifier, hold `LogWindowPresenter` |
| `Tests/ServiceDockCoreTests/StartupOrderTests.swift` | modify | startup mode + new-field persistence tests |
| `Tests/ServiceDockCoreTests/RestartPolicyTests.swift` | create | restart policy tests |
| `Tests/ServiceDockCoreTests/ConfigTransferTests.swift` | create | config transfer tests |
| `README.md` | modify | document the features |

---

### Task 1: Core — new config fields and parallel stage plan

**Files:**
- Modify: `Sources/ServiceDockCore/StartupOrder.swift`
- Modify: `Sources/ServiceDockCore/ConfigStore.swift`
- Modify: `Sources/ServiceDockCore/ServiceConfig.swift`
- Test: `Tests/ServiceDockCoreTests/StartupOrderTests.swift`

**Interfaces:**
- Produces:
  - `public enum StartupMode: String, Codable, CaseIterable, Hashable, Sendable { case staged, parallel }`
  - `StartPlan.stages(_ items: [(id: UUID, stage: Int)], mode: StartupMode = .staged) -> [[UUID]]`
  - `AppConfig.startupMode: StartupMode`, `AppConfig.notifyOnCrash: Bool`
  - `AppConfig.init(services:stageTimeoutSeconds:commandPresets:startupMode: = .staged, notifyOnCrash: = true)`
  - `ServiceConfig.autoRestart: Bool`; `ServiceConfig.init(..., learnedPorts:, autoRestart: Bool = false)`

- [ ] **Step 1: Write the failing tests** — append to `Tests/ServiceDockCoreTests/StartupOrderTests.swift`:

```swift
@Suite("Startup mode")
struct StartupModeTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test("parallel mode puts every service in one stage, in list order")
    func parallel() {
        #expect(StartPlan.stages([(a, 2), (b, 1), (c, 3)], mode: .parallel) == [[a, b, c]])
    }

    @Test("parallel mode with no services yields no stages")
    func parallelEmpty() {
        #expect(StartPlan.stages([], mode: .parallel).isEmpty)
    }

    @Test("staged is the default mode")
    func stagedDefault() {
        #expect(StartPlan.stages([(a, 2), (b, 1)]) == StartPlan.stages([(a, 2), (b, 1)], mode: .staged))
    }

    @Test("old config files load staged, with notifications on and auto-restart off")
    func legacyDefaults() throws {
        let json = """
        {"services":[{"id":"6F1C2B3A-0000-4000-8000-000000000001","name":"auth","path":"/a",
        "command":"yarn dev","icon":"server.rack"}]}
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.startupMode == .staged)
        #expect(config.notifyOnCrash)
        #expect(config.services.first?.autoRestart == false)
    }

    @Test("startup mode, notify and auto-restart round-trip")
    func roundTrip() throws {
        let service = ServiceConfig(name: "auth", path: "/a", command: "x", autoRestart: true)
        let config = AppConfig(services: [service], startupMode: .parallel, notifyOnCrash: false)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StartupModeTests`
Expected: compile errors — `cannot find 'StartupMode'`, `extra argument 'mode'`, `extra argument 'autoRestart'`.

- [ ] **Step 3: Add `StartupMode` and the `mode` parameter** — in `Sources/ServiceDockCore/StartupOrder.swift`, insert above `public enum StartPlan` and replace `stages`:

```swift
/// How Run All starts services: stage by stage, or all at once.
public enum StartupMode: String, Codable, CaseIterable, Hashable, Sendable {
    case staged
    case parallel
}
```

```swift
    /// Lowest stage first; inside a stage the original list order is kept.
    /// In `.parallel` every service is one stage, so nothing waits for anything.
    public static func stages(_ items: [(id: UUID, stage: Int)], mode: StartupMode = .staged) -> [[UUID]] {
        if mode == .parallel { return items.isEmpty ? [] : [items.map(\.id)] }
        let grouped = Dictionary(grouping: items, by: { $0.stage })
        return grouped.keys.sorted().map { stage in grouped[stage, default: []].map(\.id) }
    }
```

- [ ] **Step 4: Add `startupMode` and `notifyOnCrash` to `AppConfig`** — in `Sources/ServiceDockCore/ConfigStore.swift` replace the stored properties, `init` and `init(from:)` of `AppConfig` with:

```swift
    public var services: [ServiceConfig]
    /// How long Run All waits for one stage to become ready before moving on anyway.
    public var stageTimeoutSeconds: Int
    /// Saved commands offered in Edit Service.
    public var commandPresets: [String]
    /// Run All / Restart All: stage by stage, or everything at once.
    public var startupMode: StartupMode
    /// Post a macOS notification when a service dies.
    public var notifyOnCrash: Bool

    public init(services: [ServiceConfig] = [], stageTimeoutSeconds: Int = AppConfig.defaultStageTimeout,
                commandPresets: [String] = [], startupMode: StartupMode = .staged, notifyOnCrash: Bool = true) {
        self.services = services
        self.stageTimeoutSeconds = stageTimeoutSeconds
        self.commandPresets = commandPresets
        self.startupMode = startupMode
        self.notifyOnCrash = notifyOnCrash
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        services = try container.decode([ServiceConfig].self, forKey: .services)
        let timeout = try container.decodeIfPresent(Int.self, forKey: .stageTimeoutSeconds) ?? Self.defaultStageTimeout
        commandPresets = try container.decodeIfPresent([String].self, forKey: .commandPresets) ?? []
        stageTimeoutSeconds = min(max(timeout, Self.stageTimeoutRange.lowerBound), Self.stageTimeoutRange.upperBound)
        startupMode = try container.decodeIfPresent(StartupMode.self, forKey: .startupMode) ?? .staged
        notifyOnCrash = try container.decodeIfPresent(Bool.self, forKey: .notifyOnCrash) ?? true
    }
```

- [ ] **Step 5: Add `autoRestart` to `ServiceConfig`** — in `Sources/ServiceDockCore/ServiceConfig.swift`:

After `public var freesPortsOnStart: Bool` add:

```swift
    /// Start the service again (with back-off, see `RestartPolicy`) when it exits on its own.
    public var autoRestart: Bool
```

Replace the memberwise `init` signature and body end:

```swift
    public init(id: UUID = UUID(), name: String, path: String, command: String, url: String? = nil,
                icon: String? = nil, readyPattern: String? = nil, startStage: Int = 1,
                freesPortsOnStart: Bool = true, ports: [Int] = [], learnedPorts: [Int] = [],
                autoRestart: Bool = false) {
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
        self.autoRestart = autoRestart
    }
```

In `init(from:)`, after the `freesPortsOnStart` line add:

```swift
        autoRestart = try container.decodeIfPresent(Bool.self, forKey: .autoRestart) ?? false
```

- [ ] **Step 6: Run all tests**

Run: `swift test`
Expected: all suites pass, including `Startup mode` (5 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/ServiceDockCore Tests/ServiceDockCoreTests/StartupOrderTests.swift
git commit -m "feat(core): startup mode, notify-on-crash and auto-restart settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Core — RestartPolicy

**Files:**
- Create: `Sources/ServiceDockCore/RestartPolicy.swift`
- Test: `Tests/ServiceDockCoreTests/RestartPolicyTests.swift`

**Interfaces:**
- Produces:
  - `public struct RestartPolicy: Equatable, Sendable`
  - `RestartPolicy.delays: [Duration]` (`[.seconds(2), .seconds(5), .seconds(10)]`), `RestartPolicy.stableAfter: TimeInterval` (`60`)
  - `enum Decision: Equatable, Sendable { case restart(after: Duration, attempt: Int); case giveUp }`
  - `mutating func crashed(at: Date) -> Decision`, `mutating func becameRunning(at: Date)`, `mutating func reset()`, `var attempts: Int { get }`

- [ ] **Step 1: Write the failing tests** — create `Tests/ServiceDockCoreTests/RestartPolicyTests.swift`:

```swift
import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Restart policy")
struct RestartPolicyTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("backs off 2s, 5s, 10s, then gives up")
    func sequence() {
        var policy = RestartPolicy()
        #expect(policy.crashed(at: t0) == .restart(after: .seconds(2), attempt: 1))
        #expect(policy.crashed(at: t0 + 3) == .restart(after: .seconds(5), attempt: 2))
        #expect(policy.crashed(at: t0 + 9) == .restart(after: .seconds(10), attempt: 3))
        #expect(policy.crashed(at: t0 + 20) == .giveUp)
    }

    @Test("running for 60 seconds starts the count over")
    func stableRunResets() {
        var policy = RestartPolicy()
        _ = policy.crashed(at: t0)
        _ = policy.crashed(at: t0 + 3)
        policy.becameRunning(at: t0 + 10)
        #expect(policy.crashed(at: t0 + 70) == .restart(after: .seconds(2), attempt: 1))
    }

    @Test("running for less than 60 seconds keeps counting")
    func shortRunKeepsCount() {
        var policy = RestartPolicy()
        _ = policy.crashed(at: t0)
        policy.becameRunning(at: t0 + 5)
        #expect(policy.crashed(at: t0 + 30) == .restart(after: .seconds(5), attempt: 2))
    }

    @Test("crashing before ever running keeps counting")
    func neverRan() {
        var policy = RestartPolicy()
        _ = policy.crashed(at: t0)
        #expect(policy.crashed(at: t0 + 500) == .restart(after: .seconds(5), attempt: 2))
    }

    @Test("reset starts over")
    func reset() {
        var policy = RestartPolicy()
        _ = policy.crashed(at: t0)
        _ = policy.crashed(at: t0 + 1)
        policy.reset()
        #expect(policy.attempts == 0)
        #expect(policy.crashed(at: t0 + 2) == .restart(after: .seconds(2), attempt: 1))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RestartPolicyTests`
Expected: compile error — `cannot find 'RestartPolicy' in scope`.

- [ ] **Step 3: Implement** — create `Sources/ServiceDockCore/RestartPolicy.swift`:

```swift
import Foundation

/// Decides whether a crashed service is started again, and after how long.
/// A service that stayed running for `stableAfter` seconds gets a fresh set of attempts.
public struct RestartPolicy: Equatable, Sendable {
    /// Wait before each automatic restart; its count is the maximum number of attempts.
    public static let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(10)]
    public static let stableAfter: TimeInterval = 60

    public enum Decision: Equatable, Sendable {
        case restart(after: Duration, attempt: Int)
        case giveUp
    }

    public private(set) var attempts = 0
    private var runningSince: Date?

    public init() {}

    public mutating func becameRunning(at date: Date) {
        runningSince = date
    }

    public mutating func crashed(at date: Date) -> Decision {
        if let runningSince, date.timeIntervalSince(runningSince) >= Self.stableAfter { attempts = 0 }
        runningSince = nil
        guard attempts < Self.delays.count else { return .giveUp }
        attempts += 1
        return .restart(after: Self.delays[attempts - 1], attempt: attempts)
    }

    public mutating func reset() {
        attempts = 0
        runningSince = nil
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter RestartPolicyTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ServiceDockCore/RestartPolicy.swift Tests/ServiceDockCoreTests/RestartPolicyTests.swift
git commit -m "feat(core): restart policy with back-off

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Core — ConfigTransfer

**Files:**
- Create: `Sources/ServiceDockCore/ConfigTransfer.swift`
- Test: `Tests/ServiceDockCoreTests/ConfigTransferTests.swift`

**Interfaces:**
- Consumes: `AppConfig` (Task 1), `ServiceConfig.abbreviate(_:home:)`, `ServiceConfig.expandedPath(home:)`
- Produces (all `public static` on `public enum ConfigTransfer`):
  - `sameName(_ a: String, _ b: String) -> Bool`
  - `commonRoot(of paths: [String]) -> String?`
  - `remap(_ path: String, from oldRoot: String, to newRoot: String, home: String) -> String`
  - `remapping(_ config: AppConfig, from oldRoot: String, to newRoot: String, home: String) -> AppConfig`
  - `portable(_ config: AppConfig, home: String) -> AppConfig`
  - `merge(local: AppConfig, imported: AppConfig) -> AppConfig`
  - `replace(local: AppConfig, imported: AppConfig) -> AppConfig`

- [ ] **Step 1: Write the failing tests** — create `Tests/ServiceDockCoreTests/ConfigTransferTests.swift`:

```swift
import Foundation
import Testing
@testable import ServiceDockCore

@Suite("Config transfer")
struct ConfigTransferTests {
    let home = "/Users/dev"

    func service(_ name: String, _ path: String, command: String = "yarn dev") -> ServiceConfig {
        ServiceConfig(name: name, path: path, command: command)
    }

    // MARK: common root

    @Test("common root is the shared parent folder")
    func root() {
        let paths = ["~/p/genie/auth", "~/p/genie/profile", "~/p/genie/genie-fe"]
        #expect(ConfigTransfer.commonRoot(of: paths) == "~/p/genie")
    }

    @Test("common root of a single path is its parent")
    func rootOfOne() {
        #expect(ConfigTransfer.commonRoot(of: ["~/p/genie/auth"]) == "~/p/genie")
    }

    @Test("common root compares whole folder names")
    func rootWholeComponents() {
        #expect(ConfigTransfer.commonRoot(of: ["~/p/app", "~/p/apple"]) == "~/p")
    }

    @Test("trailing slashes are ignored")
    func rootTrailingSlash() {
        #expect(ConfigTransfer.commonRoot(of: ["~/p/a/", "~/p/b"]) == "~/p")
    }

    @Test("no shared folder, or no paths, yields nil")
    func noRoot() {
        #expect(ConfigTransfer.commonRoot(of: ["/srv/a", "/opt/b"]) == nil)
        #expect(ConfigTransfer.commonRoot(of: []) == nil)
    }

    // MARK: remap

    @Test("remap moves a path under the new root and abbreviates home")
    func remap() {
        let moved = ConfigTransfer.remap("~/p/genie/auth", from: "~/p/genie", to: "/Users/dev/work/genie/", home: home)
        #expect(moved == "~/work/genie/auth")
    }

    @Test("remap of the root itself is the new root")
    func remapRoot() {
        #expect(ConfigTransfer.remap("~/p/genie", from: "~/p/genie", to: "/srv/genie", home: home) == "/srv/genie")
    }

    @Test("remap leaves paths outside the old root alone")
    func remapOutside() {
        #expect(ConfigTransfer.remap("~/p/genieX/auth", from: "~/p/genie", to: "/x", home: home) == "~/p/genieX/auth")
    }

    @Test("remapping a config moves every service")
    func remapConfig() {
        let config = AppConfig(services: [service("auth", "~/p/genie/auth"), service("fe", "~/p/genie/fe")])
        let moved = ConfigTransfer.remapping(config, from: "~/p/genie", to: "/Users/dev/code/genie", home: home)
        #expect(moved.services.map(\.path) == ["~/code/genie/auth", "~/code/genie/fe"])
    }

    // MARK: portable

    @Test("portable writes paths under home as ~ and leaves others alone")
    func portable() {
        let config = AppConfig(services: [service("a", "/Users/dev/p/a"), service("b", "/srv/b"), service("c", "~/c")])
        let result = ConfigTransfer.portable(config, home: home)
        #expect(result.services.map(\.path) == ["~/p/a", "/srv/b", "~/c"])
    }

    // MARK: merge

    @Test("merge updates a same-name service and keeps its local id")
    func mergeUpdates() {
        let local = service("Auth", "~/old", command: "old")
        let incoming = service(" auth ", "~/new", command: "new")
        let merged = ConfigTransfer.merge(local: AppConfig(services: [local]), imported: AppConfig(services: [incoming]))
        #expect(merged.services.count == 1)
        #expect(merged.services[0].id == local.id)
        #expect(merged.services[0].command == "new")
        #expect(merged.services[0].path == "~/new")
    }

    @Test("merge keeps local-only services and appends new ones with a fresh id")
    func mergeAppends() {
        let local = service("auth", "~/a")
        let incoming = service("fe", "~/fe")
        let merged = ConfigTransfer.merge(local: AppConfig(services: [local]), imported: AppConfig(services: [incoming]))
        #expect(merged.services.map(\.name) == ["auth", "fe"])
        #expect(merged.services[1].id != incoming.id)
    }

    @Test("merge combines presets and keeps the local startup settings")
    func mergeSettings() {
        let local = AppConfig(stageTimeoutSeconds: 30, commandPresets: ["yarn dev"], startupMode: .parallel,
                              notifyOnCrash: false)
        let imported = AppConfig(stageTimeoutSeconds: 120, commandPresets: ["pnpm dev", "yarn dev", "pnpm dev"],
                                 startupMode: .staged, notifyOnCrash: true)
        let merged = ConfigTransfer.merge(local: local, imported: imported)
        #expect(merged.commandPresets == ["yarn dev", "pnpm dev"])
        #expect(merged.stageTimeoutSeconds == 30)
        #expect(merged.startupMode == .parallel)
        #expect(merged.notifyOnCrash == false)
    }

    // MARK: replace

    @Test("replace takes the imported config but keeps ids of same-name services")
    func replace() {
        let localAuth = service("auth", "~/a")
        let localOld = service("old", "~/old")
        let imported = AppConfig(services: [service("AUTH", "~/a2"), service("fe", "~/fe")], stageTimeoutSeconds: 120,
                                 commandPresets: ["pnpm dev"], startupMode: .parallel, notifyOnCrash: false)
        let result = ConfigTransfer.replace(local: AppConfig(services: [localAuth, localOld]), imported: imported)
        #expect(result.services.map(\.name) == ["AUTH", "fe"])
        #expect(result.services[0].id == localAuth.id)
        #expect(result.services[0].path == "~/a2")
        #expect(result.services[1].id != localOld.id)
        #expect(result.stageTimeoutSeconds == 120)
        #expect(result.commandPresets == ["pnpm dev"])
        #expect(result.startupMode == .parallel)
        #expect(result.notifyOnCrash == false)
    }

    @Test("replace gives services with duplicate names distinct ids")
    func replaceDuplicates() {
        let local = service("auth", "~/a")
        let imported = AppConfig(services: [service("auth", "~/a"), service("auth", "~/b")])
        let result = ConfigTransfer.replace(local: AppConfig(services: [local]), imported: imported)
        #expect(result.services[0].id == local.id)
        #expect(result.services[1].id != local.id)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigTransferTests`
Expected: compile error — `cannot find 'ConfigTransfer' in scope`.

- [ ] **Step 3: Implement** — create `Sources/ServiceDockCore/ConfigTransfer.swift`:

```swift
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ConfigTransferTests`
Expected: 15 tests pass.

- [ ] **Step 5: Run the full suite and commit**

Run: `swift test`
Expected: all pass.

```bash
git add Sources/ServiceDockCore/ConfigTransfer.swift Tests/ServiceDockCoreTests/ConfigTransferTests.swift
git commit -m "feat(core): config transfer — common root, remap, merge, replace

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: App — parallel start

**Files:**
- Modify: `Sources/ServiceDock/AppModel.swift`
- Modify: `Sources/ServiceDock/Views/StartupOrderPage.swift`

**Interfaces:**
- Consumes: `StartupMode`, `StartPlan.stages(_:mode:)`, `AppConfig.startupMode`, `AppConfig.notifyOnCrash` (Task 1)
- Produces:
  - `AppModel.startupMode: StartupMode { get }`, `AppModel.setStartupMode(_ mode: StartupMode)`
  - `AppModel.notifyOnCrash: Bool { get }` (loaded and saved here; used in Task 6)
  - `private var appConfig: AppConfig` in `AppModel` — the single source for what `save()` writes (used by Task 7)

- [ ] **Step 1: Add state to `AppModel`** — in `Sources/ServiceDock/AppModel.swift`, after the `commandPresets` property add:

```swift
    /// Run All starts stage by stage, or everything at once.
    private(set) var startupMode = StartupMode.staged
    /// Post a macOS notification when a service dies.
    private(set) var notifyOnCrash = true
```

In `init`, after `commandPresets = config.commandPresets` add:

```swift
            startupMode = config.startupMode
            notifyOnCrash = config.notifyOnCrash
```

- [ ] **Step 2: Route saving through one `appConfig`** — replace `save()` with:

```swift
    /// Everything written to `services.json` (and to an exported file).
    private var appConfig: AppConfig {
        AppConfig(services: runtimes.map(\.config), stageTimeoutSeconds: stageTimeoutSeconds,
                  commandPresets: commandPresets, startupMode: startupMode, notifyOnCrash: notifyOnCrash)
    }

    private func save() {
        do {
            try ConfigStore.save(appConfig, to: storeURL)
            storageError = nil
        } catch {
            logger.error("Config save failed: \(error.localizedDescription, privacy: .public)")
            storageError = error.localizedDescription
        }
    }
```

- [ ] **Step 3: Use the mode in Run All** — update the doc comments and `runStaged`:

```swift
    /// Starts every service, stage by stage or all at once (see `startupMode`).
    func runAll() {
```

```swift
    /// Stops everything, waits until the old processes are gone (ports free), then starts again (see `startupMode`).
    func restartAll() {
```

First line of `runStaged()` becomes:

```swift
        let stages = StartPlan.stages(runtimes.map { (id: $0.id, stage: $0.config.startStage) }, mode: startupMode)
```

After `setStageTimeout(_:)` add:

```swift
    func setStartupMode(_ mode: StartupMode) {
        guard mode != startupMode else { return }
        startupMode = mode
        save()
    }
```

- [ ] **Step 4: Add the Staged / Parallel switch** — in `Sources/ServiceDock/Views/StartupOrderPage.swift`:

In `header`, replace `Spacer()` with:

```swift
            Spacer()
            Picker("Startup mode", selection: Binding(get: { model.startupMode }, set: { model.setStartupMode($0) })) {
                Text("Staged").tag(StartupMode.staged)
                Text("Parallel").tag(StartupMode.parallel)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            .help("Staged: start in order, waiting for each stage. Parallel: start everything at once.")
```

Replace `explanation` with:

```swift
    private var explanation: some View {
        Text(model.startupMode == .parallel
             ? "โหมด Parallel: Run All เริ่มทุก service พร้อมกันทันที ไม่รอกัน — เลขลำดับยังเก็บไว้ใช้เมื่อกลับไปโหมด Staged."
             : "ใส่เลขลำดับให้แต่ละ service — เลขน้อยเริ่มก่อน, เลขเท่ากันเริ่มพร้อมกัน. "
               + "ลำดับถัดไปจะเริ่มเมื่อทุกตัวในลำดับก่อนหน้าพร้อมแล้ว (เจอ log เช่น “compiled successfully”).")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText)
    }
```

In `summary`, change the first line to:

```swift
        let steps = StartPlan.stages(model.runtimes.map { (id: $0.id, stage: $0.config.startStage) },
                                     mode: model.startupMode)
```

In `body`, disable the stage editors and timeout in Parallel — change the card and timeout row:

```swift
                    VStack(spacing: 0) {
                        ForEach(model.runtimes) { runtime in
                            OrderRow(runtime: runtime)
                            if runtime.id != model.runtimes.last?.id { Divider().overlay(Theme.stroke) }
                        }
                    }
                    .card()
                    .disabled(model.startupMode == .parallel)
                    .opacity(model.startupMode == .parallel ? 0.5 : 1)
```

```swift
            timeoutRow
                .disabled(model.startupMode == .parallel)
                .opacity(model.startupMode == .parallel ? 0.5 : 1)
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 6: Manual check**

Run: `scripts/build-app.sh && open build/ServiceDock.app`
Check: ⋯ → Startup Order… shows the Staged / Parallel switch. Switch to Parallel → stage fields and timeout grey out, summary shows one row with every service. Run All → every service goes to Starting at once, no "Starting stage" banner. Quit and reopen → the mode is still Parallel. Switch back to Staged.

- [ ] **Step 7: Commit**

```bash
git add Sources/ServiceDock/AppModel.swift Sources/ServiceDock/Views/StartupOrderPage.swift
git commit -m "feat: parallel startup mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: App — auto-restart on crash

**Files:**
- Modify: `Sources/ServiceDock/Runtime/ServiceRuntime.swift`
- Modify: `Sources/ServiceDock/Views/ServiceEditorView.swift`

**Interfaces:**
- Consumes: `RestartPolicy` (Task 2), `ServiceConfig.autoRestart` (Task 1)
- Produces:
  - `enum CrashEvent: Equatable { case crashed(exitCode: Int32); case gaveUp(attempts: Int) }` (top level, app target)
  - `ServiceRuntime.onCrash: (@MainActor (ServiceRuntime, CrashEvent) -> Void)?` — called with `.crashed` when a service without auto-restart goes Down, and `.gaveUp` when auto-restart stops trying.

- [ ] **Step 1: Add `CrashEvent` and the new state** — in `Sources/ServiceDock/Runtime/ServiceRuntime.swift`, above `@Observable @MainActor final class ServiceRuntime`, add:

```swift
/// A crash worth telling the user about.
enum CrashEvent: Equatable {
    /// Exited on its own and auto-restart is off.
    case crashed(exitCode: Int32)
    /// Auto-restart tried `attempts` times and stopped.
    case gaveUp(attempts: Int)
}

```

After `@ObservationIgnored private let onConfigChange: @MainActor () -> Void` add:

```swift
    /// Told when a crash should be reported. Set by `AppModel`.
    @ObservationIgnored var onCrash: (@MainActor (ServiceRuntime, CrashEvent) -> Void)?
    @ObservationIgnored private var restartPolicy = RestartPolicy()
    /// Pending automatic restart after a crash.
    @ObservationIgnored private var autoRestartTask: Task<Void, Never>?
```

- [ ] **Step 2: Separate a user start from an automatic one** — rename the current `func start()` to `private func startProcess()` (body unchanged), and add above it:

```swift
    /// A start asked for by the user (or Run All): forgets earlier crashes.
    func start() {
        cancelAutoRestart()
        startProcess()
    }
```

- [ ] **Step 3: Cancel pending restarts on user actions** — make these edits:

`stop()`:

```swift
    func stop() {
        cancelAutoRestart()
        restartAfterExit = false
        if case .down = status { status = .stopped }
        requestStop()
    }
```

`restart()`:

```swift
    func restart() {
        cancelAutoRestart()
        guard status.isAlive else { return start() }
        restartAfterExit = true
        requestStop()
    }
```

`terminateForQuit()` — add as the first line:

```swift
        autoRestartTask?.cancel()
```

`update(config:)` — add before `config = newConfig`:

```swift
        if !newConfig.autoRestart { cancelAutoRestart() }
```

- [ ] **Step 4: Tell the policy when the service is up** — add this method in the `// MARK: - Process events` section:

```swift
    private func markRunning() {
        status = .running
        restartPolicy.becameRunning(at: Date())
    }
```

In `append(raw:)` replace `if status == .starting { status = .running }` with:

```swift
            if status == .starting { markRunning() }
```

In `refresh(stats:now:)` replace `status = .running` with:

```swift
            markRunning()
```

- [ ] **Step 5: Handle the crash** — at the end of `processExited(code:)`, replace the `if restartAfterExit { … }` block with:

```swift
        if restartAfterExit {
            restartAfterExit = false
            start()
        } else if !wasStopping {
            handleCrash(code: code)
        }
```

And add after `processExited`:

```swift
    /// Restarts with back-off when auto-restart is on; otherwise (or when it gives up) reports the crash.
    private func handleCrash(code: Int32) {
        guard config.autoRestart else {
            onCrash?(self, .crashed(exitCode: code))
            return
        }
        switch restartPolicy.crashed(at: Date()) {
        case .giveUp:
            note("Gave up after \(RestartPolicy.delays.count) restarts", level: .error)
            onCrash?(self, .gaveUp(attempts: RestartPolicy.delays.count))
        case .restart(let delay, let attempt):
            note("Crashed — restarting in \(delay.components.seconds)s (\(attempt)/\(RestartPolicy.delays.count))",
                 level: .warn)
            autoRestartTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, case .down = self.status else { return }
                self.autoRestartTask = nil
                self.startProcess()
            }
        }
    }

    private func cancelAutoRestart() {
        autoRestartTask?.cancel()
        autoRestartTask = nil
        restartPolicy.reset()
    }
```

- [ ] **Step 6: Add the toggle to Edit Service** — in `Sources/ServiceDock/Views/ServiceEditorView.swift`, in the second `Section`, right after the `TextField("Ready pattern …")` line, add:

```swift
                Toggle("Restart if it crashes (up to \(RestartPolicy.delays.count) times)", isOn: $draft.autoRestart)
```

- [ ] **Step 7: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 8: Manual check**

Run: `scripts/build-app.sh && open build/ServiceDock.app`
Add a test service: Folder `/tmp`, Command `sleep 3; exit 1`, toggle **Restart if it crashes** on. Run it. Its log shows "Crashed — restarting in 2s (1/3)", then 5s (2/3), 10s (3/3), then "Gave up after 3 restarts", and it stays Down. Run it again → the count starts at 1/3. Press Stop during a pending restart → it stays Stopped. Toggle off, Run → it goes Down once with no restart.

- [ ] **Step 9: Commit**

```bash
git add Sources/ServiceDock/Runtime/ServiceRuntime.swift Sources/ServiceDock/Views/ServiceEditorView.swift
git commit -m "feat: auto-restart crashed services with back-off

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: App — crash notifications

**Files:**
- Create: `Sources/ServiceDock/Runtime/CrashNotifier.swift`
- Create: `Sources/ServiceDock/Views/LogWindowPresenter.swift`
- Modify: `Sources/ServiceDock/AppModel.swift`
- Modify: `Sources/ServiceDock/ServiceDockApp.swift`
- Modify: `Sources/ServiceDock/Views/MenuBarPanel.swift`

**Interfaces:**
- Consumes: `CrashEvent`, `ServiceRuntime.onCrash` (Task 5), `AppModel.notifyOnCrash` (Task 4)
- Produces:
  - `CrashNotifier.activate(onOpen: @escaping @MainActor (UUID) -> Void)`, `CrashNotifier.post(serviceID: UUID, title: String, body: String)`
  - `LogWindowPresenter.show(serviceID: UUID, model: AppModel)`
  - `AppModel.notifier: CrashNotifier`, `AppModel.setNotifyOnCrash(_ enabled: Bool)`

- [ ] **Step 1: Create the notifier** — `Sources/ServiceDock/Runtime/CrashNotifier.swift`:

```swift
import Foundation
import UserNotifications

/// Posts "service died" notifications and reports which service the user clicked.
@MainActor
final class CrashNotifier: NSObject {
    nonisolated static let serviceKey = "serviceID"

    /// `UNUserNotificationCenter` crashes outside an app bundle (e.g. `swift run`).
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var onOpen: (@MainActor (UUID) -> Void)?
    private var didRequestPermission = false

    func activate(onOpen: @escaping @MainActor (UUID) -> Void) {
        guard Self.isAvailable else { return }
        self.onOpen = onOpen
        UNUserNotificationCenter.current().delegate = self
    }

    func post(serviceID: UUID, title: String, body: String) {
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = serviceID.uuidString
        content.userInfo = [Self.serviceKey: serviceID.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let needsPermission = !didRequestPermission
        didRequestPermission = true
        Task {
            if needsPermission { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
            try? await center.add(request)
        }
    }

    private func open(_ id: UUID) {
        onOpen?(id)
    }
}

extension CrashNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo[Self.serviceKey] as? String,
              let id = UUID(uuidString: text) else { return }
        await open(id)
    }

    /// Show the banner even while ServiceDock is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
```

- [ ] **Step 2: Create the log window presenter** — `Sources/ServiceDock/Views/LogWindowPresenter.swift`:

```swift
import AppKit
import SwiftUI

/// Opens a service's log window from AppKit code (a notification click), where SwiftUI's `openWindow` isn't available.
@MainActor
final class LogWindowPresenter {
    private var windows: [UUID: NSWindow] = [:]

    func show(serviceID: UUID, model: AppModel) {
        guard model.runtime(for: serviceID) != nil else { return }
        let window = windows[serviceID] ?? makeWindow(serviceID: serviceID, model: model)
        windows[serviceID] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow(serviceID: UUID, model: AppModel) -> NSWindow {
        let content = ServiceDetailView(serviceID: serviceID).environment(model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = model.name(of: serviceID)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
```

- [ ] **Step 3: Report crashes from `AppModel`** — in `Sources/ServiceDock/AppModel.swift`:

After `@ObservationIgnored private var startupTask: Task<Void, Never>?` add:

```swift
    /// Posts "service died" notifications. Activated by `AppDelegate`.
    @ObservationIgnored let notifier = CrashNotifier()
```

After `setStartupMode(_:)` add:

```swift
    func setNotifyOnCrash(_ enabled: Bool) {
        guard enabled != notifyOnCrash else { return }
        notifyOnCrash = enabled
        save()
    }
```

Replace `makeRuntime(_:)` with:

```swift
    private func makeRuntime(_ config: ServiceConfig) -> ServiceRuntime {
        let runtime = ServiceRuntime(
            config: config, registry: registry,
            protectedGroups: { [weak self] in Set(self?.runtimes.compactMap(\.processGroup) ?? []) },
            onConfigChange: { [weak self] in self?.save() }
        ) { [weak self] runtime, texts, level in
            self?.emit(from: runtime, texts: texts, level: level) ?? []
        }
        runtime.onCrash = { [weak self] runtime, event in self?.report(event, from: runtime) }
        return runtime
    }

    private func report(_ event: CrashEvent, from runtime: ServiceRuntime) {
        guard notifyOnCrash else { return }
        let body = switch event {
        case .crashed(let code) where code < 0: "Crashed (signal \(-code))"
        case .crashed(let code): "Crashed (exit \(code))"
        case .gaveUp(let attempts): "Gave up after \(attempts) restarts"
        }
        notifier.post(serviceID: runtime.id, title: runtime.config.name, body: body)
    }
```

- [ ] **Step 4: Activate on launch** — in `Sources/ServiceDock/ServiceDockApp.swift`, in `AppDelegate`:

After `let model = AppModel()` add:

```swift
    private let logWindows = LogWindowPresenter()
```

At the top of `applicationDidFinishLaunching(_:)` add:

```swift
        model.notifier.activate { [weak self] id in
            guard let self else { return }
            self.logWindows.show(serviceID: id, model: self.model)
        }
```

- [ ] **Step 5: Menu toggle** — in `Sources/ServiceDock/Views/MenuBarPanel.swift`, in the header `Menu`, after the `Clear All Error Counts` button (and its `.disabled` line) add:

```swift
                Toggle("Notify When a Service Dies",
                       isOn: Binding(get: { model.notifyOnCrash }, set: { model.setNotifyOnCrash($0) }))
```

- [ ] **Step 6: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 7: Manual check**

Run: `scripts/build-app.sh && open build/ServiceDock.app`
With the `/tmp` test service from Task 5 and auto-restart **off**: Run → on first crash macOS asks for notification permission; allow. A banner "<name> — Crashed (exit 1)" appears. Click it → that service's log window opens. With auto-restart **on**: no banner on the first three crashes; one banner "Gave up after 3 restarts". ⋯ → untick **Notify When a Service Dies** → crash shows no banner. Also run `swift run ServiceDock`, crash the service → no crash (notifications silently skipped). Delete the test service afterwards.

- [ ] **Step 8: Commit**

```bash
git add Sources/ServiceDock
git commit -m "feat: notify when a service dies

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: App — export / import config

**Files:**
- Create: `Sources/ServiceDock/Views/ImportPage.swift`
- Modify: `Sources/ServiceDock/AppModel.swift`
- Modify: `Sources/ServiceDock/Views/MenuBarPanel.swift`

**Interfaces:**
- Consumes: `ConfigTransfer.*` (Task 3), `AppModel.appConfig` (Task 4), `ConfigStore.load/save`
- Produces:
  - `AppModel.ImportMode { case merge, replace }`
  - `AppModel.exportConfig(to url: URL) throws(ConfigStoreError)`
  - `AppModel.applyImport(_ imported: AppConfig, mode: ImportMode)`
  - `struct ImportDraft: Equatable { let fileName: String; let config: AppConfig }`
  - `PanelRoute.importConfig(ImportDraft)`

- [ ] **Step 1: Export and import in `AppModel`** — in `Sources/ServiceDock/AppModel.swift`, add a section before `// MARK: - Quit`:

```swift
    // MARK: - Export / Import

    enum ImportMode {
        /// Add new services, update same-name ones, keep the rest.
        case merge
        /// The imported file becomes the whole config.
        case replace
    }

    func exportConfig(to url: URL) throws(ConfigStoreError) {
        try ConfigStore.save(ConfigTransfer.portable(appConfig, home: NSHomeDirectory()), to: url)
    }

    /// Applies an imported config. Runtimes whose id survives keep running with the new settings;
    /// removed services are stopped.
    func applyImport(_ imported: AppConfig, mode: ImportMode) {
        let next = switch mode {
        case .merge: ConfigTransfer.merge(local: appConfig, imported: imported)
        case .replace: ConfigTransfer.replace(local: appConfig, imported: imported)
        }
        let keptIDs = Set(next.services.map(\.id))
        for runtime in runtimes where !keptIDs.contains(runtime.id) && runtime.status.isAlive {
            runtime.stop()
            retiring = retiring + [runtime]
        }
        runtimes = next.services.map { config in
            guard let existing = runtime(for: config.id) else { return makeRuntime(config) }
            existing.update(config: config)
            return existing
        }
        stageTimeoutSeconds = next.stageTimeoutSeconds
        commandPresets = next.commandPresets
        startupMode = next.startupMode
        notifyOnCrash = next.notifyOnCrash
        save()
    }
```

- [ ] **Step 2: Create the Import page** — `Sources/ServiceDock/Views/ImportPage.swift`:

```swift
import AppKit
import ServiceDockCore
import SwiftUI

/// A config file picked with Import Config…, waiting for Merge or Replace.
struct ImportDraft: Equatable {
    let fileName: String
    let config: AppConfig
}

/// Shows what an imported config contains, lets the user move its folders to a new root, then merges or replaces.
struct ImportPage: View {
    @Environment(AppModel.self) private var model
    let draft: ImportDraft
    let onDone: () -> Void

    /// Folder chosen with Choose New Root…; `nil` keeps the paths from the file.
    @State private var newRoot: String?

    private var home: String { NSHomeDirectory() }
    private var oldRoot: String? { ConfigTransfer.commonRoot(of: draft.config.services.map(\.path)) }

    private var config: AppConfig {
        guard let oldRoot, let newRoot else { return draft.config }
        return ConfigTransfer.remapping(draft.config, from: oldRoot, to: newRoot, home: home)
    }

    private var missingCount: Int { config.services.count { !folderExists($0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    if oldRoot != nil { rootRow }
                    if !config.services.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(config.services) { service in
                                ImportRow(service: service, exists: folderExists(service), isUpdate: isUpdate(service))
                                if service.id != config.services.last?.id { Divider().overlay(Theme.stroke) }
                            }
                        }
                        .card()
                    }
                }
                .padding(14)
            }
            Divider().overlay(Theme.stroke)
            buttons
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onDone) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back without importing")
            IconTile(symbol: "square.and.arrow.down", size: 30, tint: Theme.accent)
            Text("Import \(draft.fileName)").font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(config.services.count) services, \(config.commandPresets.count) command presets")
                .font(.system(size: 12.5, weight: .medium))
            Text(missingCount == 0
                 ? "All folders found on this Mac."
                 : "\(missingCount) folder(s) not found on this Mac — choose the new root folder, or fix them later in Edit Service.")
                .font(.system(size: 11.5))
                .foregroundStyle(missingCount == 0 ? Theme.secondaryText : Theme.yellow)
        }
    }

    private var rootRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Root folder").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                Text(newRoot.map { ServiceConfig.abbreviate($0, home: home) } ?? oldRoot ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if newRoot != nil { Button("Undo") { newRoot = nil } }
            Button("Choose New Root…", action: chooseRoot)
        }
        .padding(10)
        .card()
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onDone).keyboardShortcut(.cancelAction)
            Button("Replace All") { finish(.replace) }
                .help("Use only the services in this file. Services not in it are stopped and removed.")
            Button("Merge") { finish(.merge) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .help("Add new services and update the ones with the same name.")
        }
        .disabled(config.services.isEmpty)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that replaces \(oldRoot ?? "the old root") on this Mac"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        newRoot = url.path
    }

    private func finish(_ mode: AppModel.ImportMode) {
        model.applyImport(config, mode: mode)
        onDone()
    }

    private func folderExists(_ service: ServiceConfig) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: service.expandedPath(home: home), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func isUpdate(_ service: ServiceConfig) -> Bool {
        model.runtimes.contains { ConfigTransfer.sameName($0.config.name, service.name) }
    }
}

private struct ImportRow: View {
    let service: ServiceConfig
    let exists: Bool
    /// A local service with the same name will be updated (Merge) instead of added.
    let isUpdate: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: service.icon, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(service.name).font(.system(size: 12.5, weight: .medium))
                    Text(isUpdate ? "update" : "new")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.stroke, in: Capsule())
                }
                Text(service.path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(exists ? Theme.green : Theme.red)
                .help(exists ? "Folder found" : "Folder not found on this Mac")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 3: Route and menu items** — in `Sources/ServiceDock/Views/MenuBarPanel.swift`:

Add `import UniformTypeIdentifiers` after `import SwiftUI`.

Add a case to `PanelRoute`:

```swift
    case importConfig(ImportDraft)
```

In `resizeTarget`, change the last case to:

```swift
        case .service, .startupOrder, .editor, .importConfig: ($detailWidth, $detailHeight, detailSize)
```

In `body`'s `switch route`, after the `.editor` case add:

```swift
            case .importConfig(let draft):
                ImportPage(draft: draft, onDone: goBack)
                    .frame(width: detailSize.width, height: detailSize.height)
```

In the header `Menu`, after the `Reveal Config File` button add:

```swift
                Button("Export Config…", action: exportConfig)
                Button("Import Config…", action: chooseImportFile)
```

Add these methods to `MenuBarPanel` (after `goBack()`):

```swift
    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "servicedock-config.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportConfig(to: url)
        } catch {
            model.storageError = error.localizedDescription
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let config = ConfigTransfer.portable(try ConfigStore.load(from: url), home: NSHomeDirectory())
            go(to: .importConfig(ImportDraft(fileName: url.lastPathComponent, config: config)))
        } catch {
            model.storageError = error.localizedDescription
        }
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 5: Manual check**

Run: `scripts/build-app.sh && open build/ServiceDock.app`
1. ⋯ → **Export Config…** → save to `~/Desktop/servicedock-config.json`. Open it: same shape as `services.json`, paths start with `~/`.
2. Copy it and edit the copy: change every path prefix `~/Documents/project/genie` to `~/Elsewhere/genie`, rename one service to a new name (e.g. `report-2`), save.
3. ⋯ → **Import Config…** → pick the copy. The Import page shows the counts, a yellow "folder(s) not found" line, ✗ on every row, and the root `~/Elsewhere/genie`. Rows show `update` except `report-2` (`new`).
4. **Choose New Root…** → pick `~/Documents/project/genie`. Rows turn ✓. **Undo** brings back ✗; choose again.
5. **Merge** → the list shows all original services plus `report-2`; a service that was running keeps running.
6. Import again → **Replace All** → `report` (no longer in the file) is stopped and removed; `report-2` remains.
7. Import a non-JSON file → the panel shows a readable error and nothing changes.
8. Re-import the original export with **Replace All** to restore your setup.

- [ ] **Step 6: Commit**

```bash
git add Sources/ServiceDock
git commit -m "feat: export and import config with root remapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: README and final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document the features** — in `README.md`:

Add these rows at the end of the Features table:

```markdown
| **Export / Import config** | เมนู ⋯ → *Export Config…* บันทึกเป็น `servicedock-config.json` (path ใต้ home เขียนเป็น `~/…`) → อีกเครื่อง *Import Config…* เลือก **Merge** (เพิ่มตัวใหม่ + อัปเดตตัวชื่อซ้ำ) หรือ **Replace All** — ถ้า folder ไม่เจอ กด *Choose New Root…* เลือก folder หลักใหม่ครั้งเดียว ทุก service ย้ายตาม |
| **Auto-restart เมื่อ crash** | toggle *Restart if it crashes* ใน Edit Service — รอ 2 / 5 / 10 วิ สูงสุด 3 ครั้ง, รันได้เกิน 60 วิ นับใหม่ |
| **แจ้งเตือนเมื่อ service ตาย** | notification ของ macOS เมื่อ service Down (ถ้าเปิด auto-restart แจ้งเฉพาะตอนยอมแพ้) คลิกเพื่อเปิด log — ปิดได้ที่ ⋯ → *Notify When a Service Dies* |
```

In the "Startup order" section, add after the first paragraph:

```markdown
ต้องการให้ทุกตัวเริ่มพร้อมกัน ไม่รอลำดับ → สลับเป็น **Parallel** ที่หัวหน้า Startup Order (บันทึกไว้, Run All / Restart All ใช้โหมดนี้; เลขลำดับยังเก็บไว้)
```

In "Build จาก source", replace the line `cd service-dock` with nothing (delete it — commands run from the repo root).

In "Limitations (v0.1)", change the first bullet to:

```markdown
- ยังไม่มี group/profile, env override ใน app, health check ผ่าน HTTP
```

- [ ] **Step 2: Full verification**

Run: `swift test`
Expected: all tests pass (previous 99 + 25 new).

Run: `scripts/build-app.sh`
Expected: `✓ Built: …/build/ServiceDock.app`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: export/import, parallel start, auto-restart, notifications

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
