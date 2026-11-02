# ServiceDock

**Run / Restart / Monitor หลาย local service จาก menu bar ของ Mac — ไม่ต้องเปิด terminal ทีละแท็บอีกต่อไป**

ServiceDock คือ macOS menu-bar app สำหรับ dev ที่ต้องรันหลาย service พร้อมกัน (เช่น microservices ที่แต่ละตัวต้อง `cd` เข้า folder แล้ว `yarn start:dev`)
ลงทะเบียน service ครั้งเดียว: **path ของ folder** + **command** แล้วกด **Run All** ทีเดียวจบ — มี restart หลังแก้ `.env`, ดู log ราย service และหน้ารวมเพื่อดูว่าตัวไหน down หรือ error

---

## Features

| | |
|---|---|
| **เมนูใน menu bar** | ไอคอน + `running/total` (เช่น `5/7`); ถ้ามีตัวไหน down/error ไอคอนจะเปลี่ยนเป็น ⚠︎ |
| **Service list** | ชื่อ, path, command, สถานะ (Stopped / Starting / Running / Stopping / Down), จำนวน error |
| **Run All / Restart All / Stop All** | สั่งทุกตัวในคลิกเดียว (`⌘R`, `⇧⌘R`) |
| **Restart รายตัว** | รอ process เก่าตายจริงก่อนเริ่มใหม่ → ไม่ชน port, ค่าใน `.env` ใหม่ถูกโหลด |
| **ตรวจจับ `.env` เปลี่ยน** | แก้ `.env`, `.env.local`, `.env.development` … หลัง service start → ขึ้น badge **env changed** กดเพื่อ restart ได้เลย |
| **Mini monitor ราย service** | หน้าต่าง Logs / Info / Actions, uptime, CPU, RAM, auto scroll, ค้นหา, filter เฉพาะ warn/error, clear, copy |
| **All Services monitor** | เปิดเป็นหน้าใน popup เดียวกัน (popup ขยายตามหน้า) กด ‹ หรือ Esc เพื่อกลับ — โหมด **Grid**: แต่ละ service เป็น tile มี log สดของตัวเอง + สถานะ/CPU/RAM/ปุ่ม run-restart — จำนวนคอลัมน์ปรับอัตโนมัติตามจำนวน service และขนาดหน้าต่าง (กรอง warn/error, ซ่อน/แสดงราย service ได้, **ลาก header เพื่อสลับตำแหน่ง**, **ลากขอบไหนก็ได้ (นอก/ใน) หรือมุมขวาล่างเพื่อปรับขนาด** — กว้างล็อกตามคอลัมน์, ดับเบิลคลิกขอบเพื่อกลับเป็นอัตโนมัติ, ปุ่ม **Default Size** คืนขนาดปกติทุก tile) หรือโหมด **Combined**: ตารางสถานะ + log รวมทุกตัวสีแยกราย service |
| **ปรับขนาด popup** | ลากมุมขวาล่างของ popup — แต่ละหน้าจำขนาดของตัวเอง, ดับเบิลคลิกมุม = ขนาดปกติ |
| **Clear error count** | คลิกขวาที่ badge แดง → *Clear Error Count* (log ยังอยู่) หรือเมนู ⋯ → *Clear All Error Counts* |
| **ไม่ทิ้ง process ค้าง** | ทุก service รันใน process group ของตัวเอง — stop/quit จะฆ่า `yarn → node → …` ทั้งต้นไม้ (SIGTERM, ไม่ตายใน 5 วิ → SIGKILL) |
| **Export / Import config** | เมนู ⋯ → *Export Config…* บันทึกเป็น `servicedock-config.json` (path ใต้ home เขียนเป็น `~/…`) → อีกเครื่อง *Import Config…* เลือก **Merge** (เพิ่มตัวใหม่ + อัปเดตตัวชื่อซ้ำ) หรือ **Replace All** — ถ้า folder ไม่เจอ กด *Choose New Root…* เลือก folder หลักใหม่ครั้งเดียว ทุก service ย้ายตาม |
| **Auto-restart เมื่อ crash** | toggle *Restart if it crashes* ใน Edit Service — รอ 2 / 5 / 10 วิ สูงสุด 3 ครั้ง, รันได้เกิน 60 วิ นับใหม่ |
| **แจ้งเตือนเมื่อ service ตาย** | notification ของ macOS เมื่อ service Down (ถ้าเปิด auto-restart แจ้งเฉพาะตอนยอมแพ้) คลิกเพื่อเปิด log — ปิดได้ที่ ⋯ → *Notify When a Service Dies* |

## ฆ่าตัวเก่าที่ถือ port ก่อนรัน

ก่อน Run / Restart ทุกครั้ง แอปจะหยุดโปรเซสเก่าที่ยังถือ port ของ service นั้นอยู่ (เหมือน `lsof -ti :8000 | xargs kill` ใน package.json แต่อัตโนมัติ)

- port มาจาก 3 ที่: ช่อง **Extra ports** ใน Edit Service, port ใน URL, และ port ที่แอป **เรียนรู้เอง** จากตอน service รันจริง (ไม่ต้องตั้งอะไร)
- ฆ่าทั้ง process group (SIGTERM ก่อน ถ้าไม่ตายใน 2 วิ → SIGKILL) และไม่แตะ service อื่นที่ ServiceDock จัดการอยู่
- ผลที่เกิดขึ้นเขียนไว้ใน log ของ service นั้น ปิดได้รายตัวด้วย toggle ใน Edit Service

## Performance

- แสดง log เป็น batch ทุก 100 ms, จัดระดับ log ด้วย byte scan (ไม่ใช้ regex), จำกัด buffer ระหว่าง process กับ UI ที่ 2 MB (ล้นแล้วข้ามของเก่าพร้อมแจ้ง), ตัดบรรทัดที่ยาวเกิน 2000 ตัวอักษร
- วัดจริง (release build, 6 service พิมพ์ log พร้อมกัน): 1,800 บรรทัด/วิ → CPU ~4%, RAM ~13 MB; 12,000 บรรทัด/วิ → CPU ~10%, RAM ~14 MB

## Startup order (ลำดับการ run)

เมนู ⋯ → **Startup Order…** พิมพ์ **เลขลำดับ** ข้างชื่อแต่ละ service (ค่าเริ่มต้น = 1 ทุกตัว, เลขน้อยเริ่มก่อน, เลขเท่ากันเริ่มพร้อมกัน) ด้านล่างมีสรุปลำดับให้ดูทันที

ต้องการให้ทุกตัวเริ่มพร้อมกัน ไม่รอลำดับ → สลับเป็น **Parallel** ที่หัวหน้า Startup Order (บันทึกไว้, Run All / Restart All ใช้โหมดนี้; เลขลำดับยังเก็บไว้)

- **Run All / Restart All** รัน Stage 1 ก่อน — ตัวที่อยู่ stage เดียวกันรันพร้อมกัน
- Stage ถัดไป **รอจนทุกตัวใน stage ก่อนหน้าพิมพ์บรรทัด "พร้อม"** (เช่น `compiled successfully`, `Nest application successfully started`) จึงเริ่ม
- ถ้า service ใน stage ไหนตาย → หยุด ไม่รัน stage ต่อไป และแจ้งใน panel
- ถ้า stage ไม่พร้อมภายในเวลาที่ตั้ง (ค่าเริ่มต้น 90 วิ ปรับได้ 10–600) → รัน stage ต่อไปเลยพร้อมแจ้งเตือน
- service ที่ไม่มีบรรทัดพร้อมที่ระบบรู้จัก ให้ตั้ง **Ready pattern** (regex) ใน Edit Service ไม่งั้นจะรอจนครบเวลา

ตัวอย่าง: `master-data` (Stage 1, ต้อง compile ก่อน) → `authentication`, `profile` (Stage 2) → `genie-fe` (Stage 3)

## ติดตั้ง (แนะนำ)

```bash
curl -fsSL https://raw.githubusercontent.com/chairat25/serviceDocks/main/scripts/install.sh | bash
```

โหลด release ล่าสุด → ตรวจ SHA-256 → ติดตั้งที่ `/Applications` → ลบ quarantine ให้อัตโนมัติ → เปิด app
ถ้า macOS ยังบล็อก script จะถามว่าจะเปิด **System Settings → Privacy & Security** ไหม แล้วกด **Open Anyway**

ติดตั้งเองจาก [Releases](https://github.com/chairat25/serviceDocks/releases/latest) (`.dmg`, universal, macOS 15+): ลากเข้า Applications แล้วรัน
`xattr -dr com.apple.quarantine /Applications/ServiceDock.app` หรือคลิกขวา → **Open**

## Build จาก source

ต้องการ macOS 15+ และ Xcode Command Line Tools (Swift 6)

```bash
scripts/build-app.sh            # → build/ServiceDock.app
scripts/build-app.sh --install  # build แล้ว copy ไป /Applications
open build/ServiceDock.app
```

Options อื่น: `--universal` (Apple Silicon + Intel), `--dmg` (ทำ .dmg/.zip สำหรับแจก)

## วิธีใช้

1. คลิกไอคอน ServiceDock ใน menu bar → **+** (Add Service)
2. กรอก
   - **Name** — เช่น `auth-service` (icon จะเดาให้จากชื่อ เปลี่ยนเองได้)
   - **Folder** — กด *Choose…* หรือพิมพ์ `~/projects/genie/services/auth`
   - **Command** — เช่น `yarn start:dev`, `pnpm dev`, `npm run start`, `docker compose up` — ปุ่ม **Presets** ข้างช่อง: เลือก command ที่บันทึกไว้/ที่ service อื่นใช้, หรือ *Add as Preset*
   - **URL** (optional) — `http://localhost:3001` เปิดจากเมนูได้
   - **Ready pattern** (optional) — regex บอกว่า service พร้อมแล้ว ปล่อยว่าง = ใช้ค่า built-in
3. กด **Run All** หรือ ▶ รายตัว
4. คลิก **›** ที่ row เพื่อเปิด log ของตัวนั้น หรือ **All Services** เพื่อดูภาพรวม
5. แก้ `.env` แล้ว → กด badge **env changed** หรือ ⟳ เพื่อ restart

### สถานะ

| สถานะ | ความหมาย |
|---|---|
| 🟢 Running | เจอบรรทัด "พร้อม" ใน log (`listening on`, `ready in`, `compiled successfully`, `Nest application successfully started`, `Local: http://…`, `Swagger documentation available`) หรือรันมาเกิน 10 วิแล้วยังไม่ตาย |
| 🟡 Starting | process เริ่มแล้ว รอบรรทัดพร้อม |
| 🟡 Stopping | ส่ง SIGTERM แล้ว รอ exit |
| 🔴 Down (exit N) | process ตายเองโดยไม่ได้สั่ง — ดู log เพื่อหาสาเหตุ |
| ⚪️ Stopped | หยุดแล้ว |

### Command รันยังไง

```
$SHELL -l -i -c "cd '<folder>' && <command>"
```

ใช้ login + interactive shell จึงโหลด `.zprofile` / `.zshrc` → เห็น `nvm`, `volta`, `yarn`, `pnpm` เหมือนเปิดใน Terminal แม้ app จะเปิดจาก Finder

### ไฟล์ config

`~/Library/Application Support/ServiceDock/services.json` (เมนู ⋯ → *Reveal Config File*) — แก้มือหรือ backup ได้

```json
{
  "services" : [
    {
      "command" : "yarn start:dev",
      "icon" : "shield.lefthalf.filled",
      "id" : "6F1C…",
      "name" : "auth-service",
      "path" : "~/projects/genie/services/auth",
      "url" : "http://localhost:3001"
    }
  ]
}
```

## Project structure

```
Sources/ServiceDockCore/   pure logic (config, log parsing, readiness, ps stats, env watch) — unit tested
Sources/ServiceDock/       app: ProcessRunner (posix_spawn + process group), ServiceRuntime, AppModel, SwiftUI views
Tests/ServiceDockCoreTests swift-testing
scripts/                   build-app.sh, Info.plist, make-icon.swift
```

## Development

```bash
swift build          # debug build
swift test           # unit tests
swift run ServiceDock
```

## Limitations (v0.1)

- ยังไม่มี group/profile, env override ใน app, health check ผ่าน HTTP
- Log เก็บใน memory ล่าสุด 3,000 บรรทัด/service และ 6,000 บรรทัดในหน้ารวม
- `.env` ตรวจเฉพาะไฟล์ใน root ของ folder service (ไม่นับ `.env.example` / `.sample` / `.template`)
