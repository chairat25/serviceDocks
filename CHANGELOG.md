# Changelog

## 0.6.0 — 2026-10-28

### Added
- All Services grid: resize a tile from any edge (top, bottom, left, right — outer and inner) or the corner; double-click an edge to reset that tile.
- **Default Size** button in the grid toolbar puts every tile back to its normal size.
- **Command presets** in Edit Service: a *Presets* menu next to Command lists saved presets and commands other services already use; *Add “…” as Preset* saves the current command, *Remove Preset* deletes one. Saved as `commandPresets` in `services.json`.

## 0.5.0 — 2026-10-28

### Added
- All Services grid: drag a tile by its header to reorder (order is saved and also used in the service list).
- Resize a tile from its bottom-right corner — width snaps to whole columns, height is free (min 140 pt); double-click the corner to go back to automatic. Sizes are saved per service (`tileSpan`, `tileHeight` in `services.json`).

## 0.4.1 — 2026-10-28

### Fixed
- NestJS lines use the level column (`LOG`/`WARN`/`ERROR`/`DEBUG`/`VERBOSE`/`FATAL`) — `DEBUG … Active log levels: …, error` no longer counts as an error.
- `Swagger documentation available at …` now counts as a ready line.

## [0.4.0] — 2026-10-28

### Added
- **Stop the old one first**: before Run / Restart, anything still listening on the service's ports is stopped (SIGTERM, then SIGKILL after 2 s; the whole process group, like Ctrl-C). Ports come from three places: ones you type in *Edit Service → Extra ports*, the port in the URL, and ports the app learns by itself (one `lsof` check 3 s and 20 s after the service is ready — no polling). Other services managed by ServiceDock are never killed this way. What was stopped is written to the service's log. Turn off per service with *Stop leftover processes on its ports before starting*.
- Stop / Restart pressed while ports are still being cleared cancels the pending start cleanly.

### Performance
- Log lines are shown in batches every 100 ms instead of per read, so a chatty service does not redraw the UI hundreds of times a second.
- Log level detection is a single byte scan instead of three regexes; ANSI stripping only runs on lines that contain an escape; the "ready" regex only runs on lines containing a keyword (and a custom ready pattern compiles once, not per line).
- Output between the reader thread and the UI goes through a bounded 2 MB mailbox; if a service floods faster than the UI can take, the oldest output is skipped (with a note in the log) instead of growing memory without limit. Lines longer than 2000 characters are cut.
- Stats refresh every 3 s (was 2 s); `.env` checks every 9 s.
- Measured with 6 services printing at once (release build): 1,800 lines/s → CPU 25% → 4%, 12,000 lines/s → CPU 105% → 10% (RAM 118 → 14 MB), 120,000 lines/s → CPU 119% → 46% (RAM 413 → 19 MB).

## [0.3.2] — 2026-10-28

### Fixed
- Services were left running (holding their ports → `[Errno 48] Address already in use` on the next start) when the app was stopped with `kill` / `pkill` / Ctrl-C / logout. The app now handles SIGTERM, SIGINT and SIGHUP by stopping all services first.
- If the app dies without a chance to clean up (`kill -9`, crash), the process groups it started are recorded in `~/Library/Application Support/ServiceDock/running.json` and stopped on the next launch. A recorded group is only killed if it is still the same process (matched by start time), so a reused pid is never touched.

## [0.3.1] — 2026-10-28

### Changed
- All Services no longer opens a separate window: it is a page inside the same menu-bar popup (the popup grows to fit), with a back button / Esc. Opening a service from a tile or error badge also stays in the popup, and back returns to the grid.

## [0.3.0] — 2026-10-28

### Added
- **All Services grid**: one tile per service, each with a live mini log, status, uptime, CPU, RAM, sparkline, error/warn badges and Run/Restart/⋯ buttons. Columns and tile height adapt to the number of services and the window size (e.g. 6 services → 3×2, 4 → 2×2, narrow window → 1 column; scrolls if tiles would get too short).
- Grid toolbar: level filter (All / Warn + Error / Errors), global auto scroll, and a *shown* menu to hide services. The previous status table + interleaved log is still available as the **Combined** mode.

## [0.2.0] — 2026-10-28

### Changed (startup order UI)
- Startup Order page is now a plain list in your service order with a number field per service (type the order directly; same number = start together) plus a live summary of the resulting order.

### Added
- **Startup order**: ⋯ menu → *Startup Order…* sets a stage (1–20) per service. Run All / Restart All start Stage 1 first; each next stage starts only after every service in the previous stage prints its ready line (a real "ready" log line, not the 10 s grace period). Services in the same stage start together.
- If a service in a stage dies, later stages are not started and the panel says so. If a stage is not ready within the timeout (default 90 s, adjustable 10–600 s), startup continues and a warning is shown. A banner with Cancel shows progress.
- Restart All now stops everything, waits until the old processes are gone, then starts in stage order.
- Old `services.json` files load fine (everything in stage 1).

## [0.1.1] — 2026-10-28

### Changed
- `›` on a service row now switches to that service's detail page **inside the menu-bar panel** (with a back button / Esc) instead of opening a separate window. "Open Logs in Window" is still available in the ⋯ menu.
- Red error badge: hover shows the latest 5 ERROR lines and explains the count; click opens the log pre-filtered to errors.

## [0.1.0] — 2026-10-28

### Added
- Menu-bar panel: service list with status, path, command, error badge, env-changed badge; header shows `running / total`.
- Add / edit / remove / reorder services (name, folder, command, optional URL, icon, ready pattern). Config saved to `~/Library/Application Support/ServiceDock/services.json`.
- Run / Stop / Restart per service; Run All (`⌘R`), Restart All (`⇧⌘R`), Stop All.
- Each service runs in its own process group through a login + interactive shell; stop/quit kills the whole tree (SIGTERM, then SIGKILL after 5 s).
- Status detection: Starting → Running from common dev-server "ready" lines or after a 10 s grace period; unexpected exit → Down (exit code / signal).
- Service window with Logs / Info / Actions tabs: uptime, CPU, RAM, CPU sparkline, error/warn counters, log search + level filter, auto scroll, clear, copy, open folder / Terminal / URL.
- All Services monitor: every service's status, URL, uptime, CPU, RAM, sparkline, error/warn counts, plus one combined colour-coded log with per-service hide/show.
- `.env*` change detection after start with one-click restart.
- Orphaned children (e.g. node outliving yarn) are killed when the leader exits, so ports are freed; exit is reported only after output drains.
- Log view pauses auto scroll when you scroll up and resumes at the bottom.
- `scripts/build-app.sh` to build an ad-hoc-signed `ServiceDock.app` (optional `--universal`, `--dmg`, `--install`).
