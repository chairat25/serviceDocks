# Config transfer, parallel start, auto-restart, crash notifications — design

Date: 2026-11-02
Status: approved

## Goals

1. Move a ServiceDock setup to another Mac (export / import the config).
2. Start all services at once instead of stage by stage.
3. Restart a service automatically when it crashes.
4. Tell the user (macOS notification) when a service dies.

Out of scope this round: profiles/groups, HTTP health checks.

## 1. Export / Import config

### UI
- ⋯ menu gains **Export Config…** and **Import Config…**.
- Export: `NSSavePanel`, default name `servicedock-config.json`. Writes the current `AppConfig` in the same JSON
  format as `services.json` (pretty-printed, sorted keys). Service paths under the home folder are written as `~/…`.
- Import: `NSOpenPanel` for `.json`. Accepts an export file or a raw `services.json`. A file that does not decode as
  `AppConfig` shows a readable error and changes nothing.
- After a file is picked, the popup navigates to a new **Import page** (same pattern as the Startup Order page):
  - Summary: number of services and presets in the file; how many folders exist on this machine.
  - **Root**: the common parent folder of the imported service paths. If at least one folder is missing,
    **Choose New Root…** (`NSOpenPanel`, directories only) remaps every path under the old root to the new root.
    Each service row shows its resulting path with ✓ (exists) or ✗ (missing).
  - Buttons: **Merge**, **Replace**, **Cancel**. Missing folders do not block import; those services can be fixed later
    in Edit Service.

### Merge rules
- Imported services are matched to local services by name, case-insensitively and trimmed.
- Match: the local service takes every imported field except `id` (kept, so its runtime/logs stay attached).
  If the service is running, the update goes through the existing `AppModel.update` path.
- No match: appended with a fresh `id`.
- Local services not in the file are kept.
- Command presets: union, local order first, then new imported ones; duplicates removed.
- `stageTimeoutSeconds` and `startupMode`: local values kept.

### Replace rules
- The imported config becomes the whole config (services, presets, timeout, startup mode).
- Imported services whose name matches a local one keep the local `id` (same as merge), so running services stay
  attached; local services absent from the file are removed via the existing remove path (stopped if running).

### Core logic — `Sources/ServiceDockCore/ConfigTransfer.swift`
Pure functions, unit tested:
- `commonRoot(of paths: [String]) -> String?` — longest shared directory prefix by path component; `nil` for no
  paths or no shared component beyond `/`. With one path, its parent folder.
- `remap(_ path: String, from oldRoot: String, to newRoot: String) -> String` — replaces the prefix only when it
  matches whole components; otherwise returns `path` unchanged. Result abbreviated to `~/…` when under home.
- `merge(local: AppConfig, imported: AppConfig) -> AppConfig`
- `replace(local: AppConfig, imported: AppConfig) -> AppConfig`
- `portable(_ config: AppConfig, home: String) -> AppConfig` — abbreviates service paths to `~/…` for export.

## 2. Parallel start

- `AppConfig.startupMode: StartupMode` (`staged` | `parallel`), default `staged`, decoded with a default when absent.
- Startup Order page: segmented control **Staged / Parallel** at the top. In Parallel the stage fields and the
  timeout control are disabled (values kept).
- `StartPlan.stages(_:mode:)`: in `.parallel` returns a single stage containing every id in list order.
  `AppModel.runStaged` uses it, so Run All and Restart All follow the mode with no second code path. A single stage
  never waits on the gate (existing behaviour for the last stage).

## 3. Auto-restart on crash

- `ServiceConfig.autoRestart: Bool`, default `false`, decoded with a default when absent. Toggle
  **Restart if it crashes** in Edit Service.
- Triggered only by a transition to `.down` (process exited without being asked). Stop, Stop All and Quit produce
  `.stopped` and never trigger it.
- Policy — `Sources/ServiceDockCore/RestartPolicy.swift`, pure and unit tested:
  - Delays: 2 s, 5 s, 10 s; at most 3 attempts.
  - The attempt counter resets once the service has been `running` for 60 s continuously.
  - API: `mutating func crashed(at:) -> Decision` where `Decision` is `.restart(after: Duration, attempt: Int)` or
    `.giveUp`; `mutating func becameRunning(at:)`, `mutating func reset()`. The 60 s reset is applied when the next crash is recorded.
- `ServiceRuntime` owns a `RestartPolicy` and a pending restart `Task`. A manual start/stop/restart or disabling the
  toggle cancels the pending task and resets the policy.
- Log notes: "Crashed — restarting in 2s (1/3)" and "Gave up after 3 restarts".

## 4. Crash notifications

- Global setting `AppConfig.notifyOnCrash: Bool`, default `true`; ⋯ menu toggle **Notify When a Service Dies**.
- `Sources/ServiceDock/Runtime/CrashNotifier.swift` wraps `UNUserNotificationCenter`:
  - Requests authorization lazily on the first notification.
  - Does nothing when `Bundle.main.bundleIdentifier` is `nil` (e.g. `swift run`).
  - Notification: title = service name, body = "Crashed (exit N)" or "Gave up after 3 restarts";
    `threadIdentifier` = service id; `userInfo` carries the service id.
  - Clicking a notification opens that service's log window via the existing opener.
- When fired:
  - `autoRestart` off: on every transition to `.down`.
  - `autoRestart` on: only when the policy gives up.

## Compatibility

All new fields (`startupMode`, `notifyOnCrash`, `autoRestart`) decode with defaults, so existing `services.json`
files and exports from older versions load unchanged.

## Testing

Unit (swift-testing, `Tests/ServiceDockCoreTests`):
- `ConfigTransferTests`: common root (several paths, one path, unrelated paths, `~` paths), remap (match, partial
  component non-match, abbreviation), merge (name match keeps id, new service appended, presets union, local
  settings kept), replace, portable.
- `RestartPolicyTests`: delay sequence, give up after 3, reset after 60 s running, no reset before 60 s.
- `StartupOrderTests`: parallel mode yields one stage in list order.
- `ConfigTests`: old JSON without new keys decodes with defaults; round-trip with new keys.

Manual (built app): export → import on a moved root (Choose New Root), merge and replace; parallel Run All;
kill a service with `kill` to see auto-restart, give-up, and the notification.
