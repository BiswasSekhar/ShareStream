# ShareStream - Agent Documentation

> **Last Updated**: 2026-02-23  
> **Project**: ShareStream - Decentralized P2P Video Streaming  
> **Stack**: Flutter (Desktop) + Go (Backend)

## Quick Overview

ShareStream is a **decentralized real-time video streaming application** that enables hosts to share video content with viewers using:
- **P2P torrent technology** for content distribution
- **WebRTC** for video calling
- **Socket.IO** for real-time signaling and sync

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SHARESTREAM ARCHITECTURE                        │
└─────────────────────────────────────────────────────────────────────────┘

                              ┌──────────────────────┐
                              │   Signaling Server   │
                              │  (Go + Socket.IO)    │
                              │   Port: 3001         │
                              └──────────┬───────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
            ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
            │    Host     │      │  Viewer 1   │      │  Viewer N   │
            │  (Flutter)  │      │  (Flutter)  │      │  (Flutter)  │
            │             │      │             │      │             │
            │ ┌─────────┐ │      │ ┌─────────┐ │      │ ┌─────────┐ │
            │ │Torrent  │ │──────│ │Torrent  │ │◄────►│ │Torrent  │ │
            │ │Engine   │ │ P2P  │ │Engine   │ │ P2P  │ │Engine   │ │
            │ │(Local)  │ │      │ │(Local)  │ │      │ │(Local)  │ │
            │ └────┬────┘ │      │ └────┬────┘ │      │ └────┬────┘ │
            │      │      │      │      │      │      │      │      │
            │ ┌────▼────┐ │      │ ┌────▼────┐ │      │ ┌────▼────┐ │
            │ │ WebRTC  │ │◄────►│ │ WebRTC  │ │◄────►│ │ WebRTC  │ │
            │ │ Service │ │      │ │ Service │ │      │ │ Service │ │
            │ └─────────┘ │      │ └─────────┘ │      │ └─────────┘ │
            └─────────────┘      └─────────────┘      └─────────────┘
```

## Components

### 1. Flutter Desktop App (`lib/`)
| File | Purpose |
|------|---------|
| `main.dart` | App entry point, theme setup |
| `app.dart` | MaterialApp configuration |
| `providers/room_provider.dart` | Central state management |
| `services/torrent_service.dart` | P2P engine management |
| `services/socket_service.dart` | Socket.IO client |
| `services/webrtc_service.dart` | Video call management |
| `screens/home_screen.dart` | Landing page (create/join room) |
| `screens/room_screen.dart` | Main video room UI |
| `theme/app_theme.dart` | Dark theme design system |

### 2. ShareStream-Engine (`go/sharestream-engine/`)
Local P2P torrent engine that runs as a subprocess.

| File | Purpose |
|------|---------|
| `cmd/main.go` | Entry point, HTTP server, IPC |
| `internal/engine/engine.go` | Torrent client (anacrolix/torrent) |
| `internal/http/server.go` | HTTP streaming server with Range support |
| `internal/ipc/ipc.go` | JSON IPC protocol for Flutter |

### 3. ShareStream-Signal (`go/sharestream-signal/`)
Signaling server for room management and WebRTC signaling.

**Features:**
- Room management (create, join, leave)
- Playback synchronization
- WebRTC signaling relay
- **Automatic Cloudflare tunnel (for external access)**

| File | Purpose |
|------|---------|
| `cmd/main.go` | Main server with Socket.IO v4 + cloudflared integration |
| `internal/server/server.go` | HTTP + Socket.IO setup |
| `internal/handlers/handlers.go` | Event handlers |
| `internal/models/models.go` | Room/Participant models |

## Key Technologies

### Flutter Dependencies
```yaml
media_kit: ^1.2.6           # Video playback
socket_io_client: ^3.0.0     # Real-time signaling
flutter_webrtc: ^1.3.0       # Video calling
file_picker: ^10.3.10        # File selection
flutter_animate: ^4.5.2      # UI animations
```

### Go Dependencies
```go
// Engine
github.com/anacrolix/torrent    # BitTorrent client

// Signal
github.com/zishang520/socket.io # Socket.IO v4 server
github.com/gorilla/mux          # HTTP routing
```

## Communication Protocols

### IPC Protocol (Flutter ↔ Engine)
Commands (Flutter → Engine):
```json
{"cmd": "seed", "filePath": "...", "trackerUrl": "..."}
{"cmd": "add", "magnetURI": "...", "trackerUrl": "..."}
{"cmd": "stop"}
{"cmd": "quit"}
```

Events (Engine → Flutter):
```json
{"event": "ready"}
{"event": "seeding", "magnetURI": "...", "serverUrl": "..."}
{"event": "added", "serverUrl": "..."}
{"event": "progress", "downloaded": 0.45, "speed": 1500000, "peers": 5}
{"event": "done"}
```

### Socket.IO Events
See `docs/SOCKET_PROTOCOL.md` for complete event documentation.

## Development Workflow

### Prerequisites
- Flutter SDK 3.x
- Go 1.21+
- GCC/Build tools (for CGO)

### Build Commands
```bash
# 1. Build Go engine (Windows)
cd go/sharestream-engine
go build -o sharestream-engine.exe ./cmd

# 2. Build Go signal server
cd go/sharestream-signal
go build -o sharestream-signal.exe ./cmd

# 3. Run Flutter app
flutter run -d windows
```

### Environment Setup
Create `.env` file:
```bash
SERVER_URL=http://localhost:3001
TURN_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your_username
TURN_CREDENTIAL=your_password
```

## Common Tasks

### Adding a New Socket Event
1. Add handler in `go/sharestream-signal/cmd/main.go` → `registerEventHandlers()`
2. Add handler in `lib/services/socket_service.dart` → `connect()`
3. Add callback in `lib/providers/room_provider.dart` if needed

### Modifying Torrent Engine
1. Update IPC protocol in `go/sharestream-engine/internal/ipc/ipc.go`
2. Add corresponding command handler
3. Update `lib/services/torrent_service.dart` to use new command

### UI Changes
- Theme constants: `lib/theme/app_theme.dart`
- Reusable widgets: `lib/widgets/common_widgets.dart`
- Glassmorphism effect: `GlassCard` widget

## File Structure

```
ShareStream/
├── lib/                      # Flutter application
│   ├── main.dart
│   ├── app.dart
│   ├── providers/
│   │   └── room_provider.dart
│   ├── services/
│   │   ├── torrent_service.dart
│   │   ├── socket_service.dart
│   │   └── webrtc_service.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   └── room_screen.dart
│   ├── widgets/
│   │   ├── common_widgets.dart
│   │   ├── video_player_widget.dart
│   │   └── video_call_overlay.dart
│   └── theme/
│       └── app_theme.dart
│
├── go/
│   ├── sharestream-engine/   # P2P torrent engine
│   │   ├── cmd/main.go
│   │   ├── internal/engine/
│   │   ├── internal/http/
│   │   └── internal/ipc/
│   │
│   └── sharestream-signal/   # Signaling server
│       ├── cmd/main.go
│       ├── internal/server/
│       ├── internal/handlers/
│       └── internal/models/
│
├── docs/                     # Additional documentation
│   ├── ARCHITECTURE.md
│   ├── SOCKET_PROTOCOL.md
│   ├── IPC_PROTOCOL.md
│   └── BUILD.md
│
└── AGENTS.md                 # This file
```

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| Engine not found | Check path in `torrent_service.dart` `_findEnginePath()` |
| Socket connection fails | Verify server URL, check `SERVER_URL` in .env |
| Video not playing | Check torrent progress, verify file format |
| WebRTC fails | Check TURN server config, firewall rules |
| Port 42069 in use | Kill process or change port in engine |

## Documentation Files

- `docs/ARCHITECTURE.md` - Detailed system architecture
- `docs/SOCKET_PROTOCOL.md` - Complete Socket.IO event reference
- `docs/IPC_PROTOCOL.md` - Engine IPC protocol specification
- `docs/BUILD.md` - Build and deployment instructions
- `docs/API.md` - REST API endpoints
- `docs/UI_GUIDE.md` - UI component usage guide

---

**Maintained by**: AI Agent  
**For updates**: Check `IMPLEMENTATION_PLAN.md` for original specs
