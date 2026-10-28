# ServiceDock — Implement Plan & Progress

> macOS menu-bar app สำหรับ run / restart / monitor หลาย local service (เช่น microservices ที่ต้อง `yarn start:dev` ทีละตัว) จากที่เดียว

อัพเดตล่าสุด: 2026-10-28

---

## 1. ปัญหา

- dev ต้องเปิด terminal หลายแท็บ `cd` เข้าแต่ละ service แล้ว `yarn start:dev` ทีละตัว
- แก้ค่าใน `.env` แล้วต้องไล่ Ctrl+C + run ใหม่ทุกตัวที่เกี่ยว
- ไม่มีภาพรวมว่าตัวไหน down / error อยู่ ต้องไล่เปิดดู log ทีละแท็บ

## 2. เป้าหมาย (Scope v0.1)

| # | Feature | สถานะ |
|---|---------|-------|
| 1 | เพิ่ม service: ชื่อ, path folder, command (เช่น `yarn start:dev`), URL (optional), icon | ✅ |
| 2 | Run / Stop / Restart รายตัว | ✅ |
| 3 | Run All / Restart All / Stop All | ✅ |
| 4 | สถานะ: Stopped / Starting / Running / Stopping / Down (exit code) | ✅ |
| 5 | Menu bar label โชว์ `running/total` | ✅ |
| 6 | Mini log monitor รายตัว (Logs / Info / Actions tab, auto scroll, clear, copy, search) | ✅ |
| 7 | หน้า All Services: สถานะทุกตัว + CPU + RAM + sparkline + log รวมทุกตัว (filter ราย service / เฉพาะ warn+error) | ✅ |
| 8 | ตรวจจับ `.env*` เปลี่ยนหลัง start → ขึ้น badge "env changed" + ปุ่ม restart | ✅ |
| 9 | นับจำนวน error / warn ต่อ service ให้เห็นตัวที่มีปัญหาทันที | ✅ |
| 10 | Quit app → kill process ทั้งหมด (ไม่มี orphan node process ค้าง port) | ✅ |
| 11 | บันทึก config ไว้ที่ `~/Library/Application Support/ServiceDock/services.json` | ✅ |

### Out of scope (ไว้ทีหลัง)

- Auto-restart เมื่อ crash
- Group / profile (เช่น run เฉพาะชุด backend)
- Env override รายตัวใน app
- Health check ด้วยการ ping port/URL
- Launch at login

## 3. Architecture

```
service-dock/
├── Package.swift                  Swift 6 SPM, macOS 15+
├── Sources/
│   ├── ServiceDockCore/           pure logic, ไม่มี UI / side effect → unit test ได้ทั้งหมด
│   │   ├── ServiceConfig.swift    model + validation + icon suggestion
│   │   ├── ServiceStatus.swift    state ของ service
│   │   ├── ShellCommand.swift     สร้าง argv: $SHELL -l -i -c "cd '<path>' && <command>"
│   │   ├── LogLine.swift          LogLine, LogLevel, ANSI strip, classify level
│   │   ├── LineSplitter.swift     แปลง byte chunk จาก pipe → บรรทัด (กัน UTF-8 ขาดกลาง)
│   │   ├── LogBuffer.swift        ring buffer จำกัดจำนวนบรรทัด
│   │   ├── Readiness.swift        ดู log ว่า server พร้อมแล้ว (Starting → Running)
│   │   ├── ProcessStats.swift     parse `ps` → CPU/RAM รวมราย process group
│   │   ├── EnvWatch.swift         snapshot mtime ของ .env* แล้ว diff
│   │   ├── ConfigStore.swift      load/save JSON
│   │   └── DurationFormat.swift   uptime "00:12:34"
│   └── ServiceDock/               app target
│       ├── ServiceDockApp.swift   MenuBarExtra + windows + AppDelegate (kill all on quit)
│       ├── AppModel.swift         รายการ service, actions, stats timer
│       ├── Runtime/
│       │   ├── ProcessRunner.swift   posix_spawn + process group (kill ทั้ง tree ได้)
│       │   ├── ServiceRuntime.swift  state ราย service (status, logs, cpu history)
│       │   └── StatsSampler.swift    เรียก `ps` แบบ async
│       └── Views/                 SwiftUI (dark theme ตาม mockup)
├── Tests/ServiceDockCoreTests/    swift-testing
└── scripts/build-app.sh           build → build/ServiceDock.app (ad-hoc sign)
```

### Design decisions

- **Process group**: spawn ด้วย `posix_spawn` + `POSIX_SPAWN_SETPGROUP` → `yarn` → `node` ลูกหลานทั้งหมดอยู่ group เดียว, stop = `kill(-pgid, SIGTERM)` แล้ว `SIGKILL` ถ้าเกิน 5 วิ → ไม่มี node ค้าง port
- **Login + interactive shell** (`-l -i`): app ที่เปิดจาก Finder ได้ PATH น้อยมาก, ต้องโหลด `.zprofile`/`.zshrc` ให้เห็น `nvm`/`yarn`/`pnpm`
- **Starting → Running**: เจอบรรทัดที่บอกว่าพร้อม (`listening on`, `ready in`, `compiled successfully`, `Nest application successfully started`, `http://localhost:` …) หรือยังไม่ตายหลัง 10 วิ
- **Down**: process exit ทั้งที่ไม่ได้สั่ง stop → `Down (exit N)`
- **Restart**: รอ process เก่า exit จริงก่อน start ใหม่ → ไม่ชน port

## 4. Tasks

- [x] Core models + tests (config, status, shell command)
- [x] Log pipeline + tests (splitter, ANSI, level, buffer, readiness)
- [x] Stats / env watch / config store + tests
- [x] ProcessRunner (posix_spawn, process group, exit source)
- [x] ServiceRuntime + AppModel
- [x] Menu bar panel
- [x] Service detail window (Logs / Info / Actions)
- [x] All Services window (stats + sparkline + combined log)
- [x] Add / Edit service window
- [x] build-app.sh + icon
- [x] README + CHANGELOG

## 5. Progress log

### 2026-10-28
- สร้าง project, ตั้งชื่อ ServiceDock
- v0.1.0 ครบ scope ข้างบน — 34 unit tests ผ่าน
- Integration test ProcessRunner กับ node server จริง: yarn → node อยู่ process group เดียว, stop แล้ว port ว่าง
- Code review แก้ไข:
  - leader (yarn) ตายแต่ node ลูกยังค้าง → kill ลูกที่เหลือทั้ง group ก่อนรายงาน exit (port ไม่ค้าง)
  - แจ้ง exit หลัง output drain ครบ + generation token กัน log ของ process เก่าไหลเข้า run ใหม่ตอน restart
  - ลบ service ที่กำลังรัน → เก็บ runtime ไว้จนกว่า process ตายจริง (kill timeout ยังทำงาน)
  - Quit: reap leader ระหว่างรอ ไม่ต้องรอครบ 3 วิทุกครั้ง
  - Stop บน service ที่ Down → Stopped (ล้างสถานะ problem)
  - Log view: text selection ราย row (ไม่ทำลาย lazy loading), เลื่อนขึ้นเอง = หยุด auto scroll, เลื่อนกลับล่างสุด = follow ต่อ

### 2026-10-28 (feedback รอบ 5) — v0.4.0 kill ของเดิม + performance
- ก่อน start/restart ฆ่าโปรเซสที่ถือ port (typed + URL + learned ด้วย lsof 2 ครั้งหลัง ready) — `PortTools`, `PortList`, `LsofParser`
- Perf: batch log 100ms, byte-scan classifier, ready prefilter + cached regex, mailbox 2MB, clamp 2000 chars
- วัดด้วย harness release-mode: CPU 25%→4% (1.8k lines/s), 105%→10% (12k), RAM 413→19 MB ที่ 120k lines/s; 76 tests

### 2026-10-28 (bug) — v0.3.2 orphan services
- อาการ: `report` ขึ้น Errno 48 เพราะ run-dev เก่าค้าง (แอปถูก `pkill` ไม่ได้ฆ่า service ลูก)
- แก้: ดัก SIGTERM/SIGINT/SIGHUP + `RunRegistry` (running.json) เก็บกวาด orphan ตอนเปิดแอปใหม่; ทดสอบ kill -9 → relaunch แล้ว port ว่าง; 56 tests

### 2026-10-28 (feedback รอบ 4) — v0.3.1
- All Services ย้ายเข้า popup เดียวกัน (PanelRoute `.overview`, ขนาดตาม screen) + back; กดเข้า service จาก tile แล้ว back กลับ grid; ลบ window แยก

### 2026-10-28 (feedback รอบ 3) — v0.3.0 Grid monitor
- All Services เป็น grid: tile ต่อ service + mini log, คอลัมน์ dynamic (`TileGrid` ใน Core, 51 tests)
- ยังมีโหมด Combined (ตาราง + log รวม) สลับด้วย segmented control

### 2026-10-28 (feedback รอบ 2) — v0.2.0 Startup order
- เพิ่ม `startStage` ต่อ service + `stageTimeoutSeconds` (config เก่า load ได้)
- Core: `StartPlan` (จัดกลุ่ม stage), `StageGate` (waiting/ready/failed/timedOut) — 47 tests ผ่าน
- `ServiceRuntime.hasSeenReadyLine` (ไม่นับ grace 10 วิ) ใช้เป็นสัญญาณพร้อม
- `AppModel.runAll/restartAll` ทำทีละ stage + `StartupState` banner (Cancel)
- หน้า Startup Order ใน panel (route `.startupOrder`)
- ทดสอบกับ service จำลอง: stage 2 รอ stage 1 พร้อมจริง, stage 1 crash → ไม่รัน stage 2

### 2026-10-28 (feedback รอบ 1)
- `›` เปลี่ยนเป็น navigation ภายใน panel (PanelRoute list/service) แทนเปิด window ใหม่
- Badge แดง: hover เห็น error ล่าสุด 5 บรรทัด, คลิกเปิด log filter Errors

- 2026-10-28 v0.4.1: Nest level column parsing (no false ERROR from "Active log levels"), Swagger line = ready. 78 tests pass.
- 2026-10-28 v0.5.0: All Services grid drag-to-reorder + corner resize (TilePacking in Core, span/height saved in ServiceConfig). 88 tests pass.
- 2026-10-28 v0.6.0: edge resize (all 4 edges), Default Size button, command presets in Edit Service (AppConfig.commandPresets). 93 tests pass.
