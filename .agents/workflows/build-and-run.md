---
description: How to run ShareStream in dev mode and build a distributable installer
---

# ShareStream — Run & Build Guide

// turbo-all

## Prerequisites

1. **Go 1.21+** — [https://go.dev/dl/](https://go.dev/dl/)
2. **Flutter SDK 3.x** — [https://flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install)
3. **GCC / MinGW** — Required for CGO (torrent engine uses C bindings)
   - Install MSYS2: [https://www.msys2.org/](https://www.msys2.org/)
   - Then run: `pacman -S mingw-w64-ucrt-x86_64-gcc`
4. **Inno Setup 6** (for installer only) — [https://jrsoftware.org/isdl.php](https://jrsoftware.org/isdl.php)

---

## Option A: Quick Dev Run (uses run.bat)

```bash
# From project root:
run.bat

# With options:
run.bat --no-tunnel    # Skip Cloudflare tunnel (local only)
run.bat --build-go     # Force rebuild Go binaries
```

This auto-builds Go binaries if needed, starts the signal server, and launches Flutter.

---

## Option B: Manual Step-by-Step Dev Run

### 1. Build Go Signal Server
```powershell
cd go\sharestream-signal
go mod tidy
go build -o sharestream-signal.exe ./cmd
```

### 2. Build Go Torrent Engine
```powershell
cd go\sharestream-engine
go mod tidy
go build -o sharestream-engine.exe ./cmd
```

### 3. Start Signal Server
```powershell
# In a separate terminal:
.\go\sharestream-signal\sharestream-signal.exe
# Add --no-tunnel to skip Cloudflare tunnel
```

### 4. Run Flutter App
```powershell
flutter pub get
flutter run -d windows
```

---

## Option C: Production Build + Installer

### Single command (automated):
```powershell
# Build everything + create installer + portable ZIP:
.\build_installer.ps1 -Version "1.0.0"

# Skip the installer (portable ZIP only):
.\build_installer.ps1 -Version "1.0.0" -CreateInstaller:$false

# Skip Flutter build (Go-only rebuild):
.\build_installer.ps1 -BuildFlutter:$false
```

### What it produces (in `dist/` folder):
- `ShareStream-Setup-1.0.0.exe` — Windows installer (requires Inno Setup 6)
- `ShareStream-Portable-1.0.0.zip` — Portable ZIP (no install needed)

### What's bundled:
- Flutter app (sharestream.exe)
- Go torrent engine (sharestream-engine.exe)
- Go signal server (sharestream-signal.exe)
- Cloudflared (auto-downloaded)
- MinGW runtime DLLs
- .env configuration file

---

## Configuration (.env file)

The `.env` file in the project root controls runtime settings:

```bash
SERVER_URL=http://localhost:3001
SIGNAL_BASE_URL=http://localhost:3001

# Optional TURN server for WebRTC NAT traversal:
# TURN_URL=turn:your-turn-server.com:3478
# TURN_USERNAME=your_username
# TURN_CREDENTIAL=your_password
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `go build` fails with CGO error | Ensure MinGW/GCC is in PATH |
| Flutter can't find engine | Run from project root so paths resolve |
| Signal server port 3001 in use | `taskkill /F /IM sharestream-signal.exe` |
| Video not playing | Check torrent engine logs in AppData |
| Inno Setup not found | Install from jrsoftware.org or use portable ZIP |
