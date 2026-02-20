# ShareStream Implementation Plan

## 1. Project Overview

ShareStream is a decentralized real-time video streaming application that enables hosts to share video content with viewers using P2P torrent technology for content distribution and WebRTC for video calling. The system consists of three main components:

- **sharestream-engine**: A Go-based local P2P engine that handles torrent seeding/downloading and provides a local HTTP server for media playback
- **sharestream-signal**: A Go-based signaling server that manages room creation, playback synchronization, and WebRTC peer connection establishment
- **Flutter Application**: Desktop application (Windows/macOS) for hosts and viewers

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SHARE STREAM ARCHITECTURE                      │
└─────────────────────────────────────────────────────────────────────────┘

                              ┌──────────────────────┐
                              │   Internet / Cloud   │
                              └──────────┬───────────┘
                                         │
                                         ▼
                         ┌───────────────────────────────┐
                         │    Koyeb / Cloud Server       │
                         │                               │
                         │  ┌─────────────────────────┐ │
                         │  │  sharestream-signal      │ │
                         │  │  (Go Binary + Socket.IO)│ │
                         │  │                          │ │
                         │  │  - Room Management       │ │
                         │  │  - Playback Sync        │ │
                         │  │  - WebRTC Signaling     │ │
                         │  │  - TURN Credentials     │ │
                         │  └─────────────────────────┘ │
                         └──────────────┬──────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    │                   │                   │
                    ▼                   ▼                   ▼
            ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
            │  Host       │     │  Viewer 1   │     │  Viewer N   │
            │  (Flutter)  │     │  (Flutter)  │     │  (Flutter)  │
            │             │     │             │     │             │
            │ ┌─────────┐ │     │ ┌─────────┐ │     │ ┌─────────┐ │
            │ │Torrent   │ │     │ │Torrent  │ │     │ │Torrent  │ │
            │ │Service   │ │     │ │Service  │ │     │ │Service  │ │
            │ └────┬────┘ │     │ └────┬────┘ │     │ └────┬────┘ │
            │      │      │     │      │      │     │      │      │
            │      ▼      │     │      ▼      │     │      ▼      │
            │ ┌─────────┐ │     │ ┌─────────┐ │     │ ┌─────────┐ │
            │ │WebRTC   │ │◄───►│ │WebRTC   │ │◄───►│ │WebRTC   │ │
            │ │Service  │ │     │ │Service  │ │     │ │Service  │ │
            │ └─────────┘ │     │ └─────────┘ │     │ └─────────┘ │
            │             │     │             │     │             │
            │ ┌─────────┐ │     │ ┌─────────┐ │     │ ┌─────────┐ │
            │ │Socket   │ │◄───►│ │Socket   │ │◄───►│ │Socket   │ │
            │ │Service  │ │     │ │Service  │ │     │ │Service  │ │
            │ └────┬────┘ │     │ └────┬────┘ │     │ └────┬────┘ │
            │      │      │     │      │      │     │      │      │
            │      ▼      │     │      ▼      │     │      ▼      │
            │ ┌─────────┐ │     │ ┌─────────┐ │     │ ┌─────────┐ │
            │ │P2P      │ │◄───►│ │P2P      │ │◄───►│ │P2P      │ │
            │ │Torrent  │ │     │ │Torrent  │ │     │ │Torrent  │ │
            │ │Network  │ │     │ │Network  │ │     │ │Network  │ │
            │ └─────────┘ │     │ └─────────┘ │     │ └─────────┘ │
            └──────┬──────┘     └─────────────┘     └─────────────┘
                   │
                   ▼
            ┌─────────────┐
            │ Local Host   │
            │              │
            │ ┌─────────┐  │
            │ │sharest- │  │
            │ │ream-eng │  │
            │ │ine.exe  │  │
            │ │         │  │
            │ │ - Seeds │  │
            │ │ - HTTP  │  │
            │ │ - DHT   │  │
            │ └─────────┘  │
            └─────────────┘

LEGEND:
  ─────  Socket.IO WebSocket Connection
  ◄────►  WebRTC Peer Connection (Mesh)
  ┌────┐  P2P Torrent Data Transfer
  └────┘

DATA FLOWS:
1. Host starts engine → seeds torrent → gets magnet URI
2. Host shares magnet via signaling server
3. Viewers receive magnet, start downloading from host + peers
4. All playback sync via signaling server
5. Video calls via WebRTC mesh network
```

## 3. Component Breakdown

### 3.1 sharestream-engine (Go Binary - Local P2P)

The local torrent engine that handles P2P content distribution.

**Location**: `go/sharestream-engine/`

**Responsibilities**:
- Seed local media files as torrents
- Download torrents from magnet URIs
- Create DHT (Distributed Hash Table) network for peer discovery
- Provide local HTTP server for media playback via Range requests
- Communicate with Flutter via stdin/stdout JSON protocol

**Key Features**:
- BitTorrent protocol implementation
- DHT bootstrap from signaling server
- HTTP range request support for seeking
- Progress reporting (download speed, peers, completion)

### 3.2 sharestream-signal (Go Binary - Signaling Server)

The central server for room management, playback sync, and WebRTC signaling.

**Location**: `go/sharestream-signal/`

**Responsibilities**:
- Room creation and management
- Participant tracking
- Playback synchronization (play/pause/seek)
- WebRTC signaling (offer/answer/ICE candidates)
- TURN credential generation
- Real-time chat relay

**Key Modules**:
- `internal/server/server.go` - HTTP server and Socket.IO setup
- `internal/handlers/handlers.go` - Socket event handlers
- `internal/sync/sync.go` - Playback synchronization manager
- `internal/turn/turn.go` - TURN credential generation

### 3.3 Flutter App Changes

**Location**: Root directory

**Key Services**:
- `lib/services/torrent_service.dart` - Manages sharestream-engine subprocess
- `lib/services/socket_service.dart` - Socket.IO client for signaling
- `lib/services/webrtc_service.dart` - WebRTC peer connections
- `lib/providers/room_provider.dart` - Room state management
- `lib/screens/room_screen.dart` - Main room UI
- `lib/widgets/video_call_overlay.dart` - Video call UI

## 4. Directory Structure

```
ShareStream/
├── go/
│   ├── sharestream-engine/
│   │   ├── cmd/
│   │   │   └── sharestream-engine/
│   │   │       └── main.go
│   │   ├── internal/
│   │   │   ├── engine/
│   │   │   │   └── engine.go
│   │   │   ├── torrent/
│   │   │   │   └── torrent.go
│   │   │   ├── dht/
│   │   │   │   └── dht.go
│   │   │   └── server/
│   │   │       └── server.go
│   │   ├── go.mod
│   │   └── go.sum
│   │
│   └── sharestream-signal/
│       ├── cmd/
│       │   └── main.go
│       ├── internal/
│       │   ├── server/
│       │   │   └── server.go
│       │   ├── handlers/
│       │   │   └── handlers.go
│       │   ├── sync/
│       │   │   └── sync.go
│       │   └── turn/
│       │       └── turn.go
│       ├── Dockerfile
│       ├── go.mod
│       └── go.sum
│
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── providers/
│   │   ├── room_provider.dart
│   │   └── settings_provider.dart
│   ├── services/
│   │   ├── torrent_service.dart
│   │   ├── socket_service.dart
│   │   ├── webrtc_service.dart
│   │   └── storage_service.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── room_screen.dart
│   │   ├── settings_screen.dart
│   │   └── about_screen.dart
│   ├── widgets/
│   │   ├── video_call_overlay.dart
│   │   ├── server_status_dialog.dart
│   │   ├── chat_panel.dart
│   │   ├── participants_list.dart
│   │   ├── player_controls.dart
│   │   └── common_widgets.dart
│   ├── theme/
│   │   └── app_theme.dart
│   ├── models/
│   │   ├── room.dart
│   │   ├── participant.dart
│   │   └── chat_message.dart
│   └── utils/
│       ├── constants.dart
│       ├── helpers.dart
│       └── extensions.dart
│
├── assets/
│   ├── icons/
│   └── images/
│
├── test/
│   └── widget_test.dart
│
├── android/
│   ├── local.properties
│   ├── settings.gradle.kts
│   ├── gradle.properties
│   ├── gradlew
│   └── gradlew.bat
│
├── windows/
│   ├── runner/
│   │   ├── main.cpp
│   │   ├── runner.exe.manifest
│   │   ├── flutter_window.cpp
│   │   ├── flutter_window.h
│   │   ├── win32_window.cpp
│   │   ├── win32_window.h
│   │   ├── utils.cpp
│   │   ├── utils.h
│   │   ├── resource.h
│   │   └── Runner.rc
│   ├── flutter/
│   │   ├── generated_plugin_registrant.cc
│   │   ├── generated_plugin_registrant.h
│   │   └── generated_config.cmake
│   └── CMakeLists.txt
│
├── macos/
│   └── Runner.xcworkspace/
│
├── ios/
│
├── pubspec.yaml
├── pubspec.lock
├── README.md
├── .env.example
├── .gitignore
├── analysis_options.yaml
├── sharestream.iml
└── telemetry-id
```

## 5. IPC Protocol (Engine Communication)

The Flutter app communicates with `sharestream-engine` via stdin/stdout using JSON messages.

### 5.1 Commands (Flutter → Engine)

```json
{
  "cmd": "seed",
  "filePath": "/path/to/video.mp4",
  "trackerUrl": "ws://localhost:3001/"
}
```

```json
{
  "cmd": "add",
  "magnetURI": "magnet:?xt=urn:btih:...",
  "trackerUrl": "ws://localhost:3001/"
}
```

```json
{
  "cmd": "stop"
}
```

```json
{
  "cmd": "quit"
}
```

### 5.2 Events (Engine → Flutter)

**Ready Event**:
```json
{
  "event": "ready"
}
```

**Seeding Event**:
```json
{
  "event": "seeding",
  "name": "video.mp4",
  "magnetURI": "magnet:?xt=urn:btih:...",
  "serverUrl": "http://localhost:42069/video.mp4"
}
```

**Added Event** (download started):
```json
{
  "event": "added",
  "name": "video.mp4",
  "serverUrl": "http://localhost:42069/video.mp4"
}
```

**Progress Event**:
```json
{
  "event": "progress",
  "downloaded": 0.45,
  "speed": 1500000,
  "peers": 5
}
```

**Done Event**:
```json
{
  "event": "done"
}
```

**Stopped Event**:
```json
{
  "event": "stopped"
}
```

**Error Event**:
```json
{
  "event": "error",
  "message": "Failed to open file"
}
```

**Info Event**:
```json
{
  "event": "info",
  "message": "Connected to DHT"
}
```

### 5.3 Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `cmd` | string | Command type: `seed`, `add`, `stop`, `quit` |
| `filePath` | string | Absolute path to media file (seed command) |
| `magnetURI` | string | Magnet URI for torrent |
| `trackerUrl` | string | WebSocket URL for DHT bootstrap |
| `event` | string | Event type: `ready`, `seeding`, `added`, `progress`, `done`, `stopped`, `error`, `info` |
| `name` | string | Torrent/file name |
| `serverUrl` | string | Local HTTP URL for playback |
| `downloaded` | float | Download progress (0.0 - 1.0) |
| `speed` | int | Download speed in bytes/second |
| `peers` | int | Number of connected peers |
| `message` | string | Error or info message |

## 6. Socket.IO Events

### 6.1 Client → Server Events

**Room Management**:
```json
{
  "event": "create-room",
  "participantId": "flutter_1234567890",
  "name": "Host",
  "capabilities": {"nativePlayback": true},
  "requestedCode": "MYROOM"
}
```

```json
{
  "event": "join-room",
  "code": "ABC12345",
  "participantId": "flutter_1234567890",
  "name": "Guest",
  "capabilities": {"nativePlayback": true}
}
```

```json
{
  "event": "leave-room"
}
```

**Torrent/Stream**:
```json
{
  "event": "torrent-magnet",
  "magnetURI": "magnet:?xt=urn:btih:...",
  "streamPath": "video.mp4",
  "name": "My Movie"
}
```

```json
{
  "event": "movie-loaded",
  "name": "My Movie",
  "duration": 7200.5
}
```

**Playback Sync**:
```json
{
  "event": "sync-play",
  "time": 125.5,
  "actionId": "1699999999999"
}
```

```json
{
  "event": "sync-pause",
  "time": 125.5,
  "actionId": "1699999999999"
}
```

```json
{
  "event": "sync-seek",
  "time": 300.0,
  "actionId": "1699999999999"
}
```

**Advanced Sync**:
```json
{
  "event": "sync-check",
  "roomCode": "ABC12345"
}
```

```json
{
  "event": "sync-report",
  "roomCode": "ABC12345",
  "playbackTime": 125.5,
  "playing": true
}
```

```json
{
  "event": "sync-correct",
  "roomCode": "ABC12345",
  "playbackTime": 125.5,
  "playing": true,
  "actionId": "1699999999999"
}
```

**WebRTC Signaling**:
```json
{
  "event": "start-webrtc",
  "peerId": "socket_id_123",
  "initiator": true
}
```

```json
{
  "event": "offer",
  "offer": {"type": "offer", "sdp": "..."},
  "to": "socket_id_123"
}
```

```json
{
  "event": "answer",
  "answer": {"type": "answer", "sdp": "..."},
  "to": "socket_id_123"
}
```

```json
{
  "event": "ice-candidate",
  "candidate": {"candidate": "...", "sdpMid": "0", "sdpMLineIndex": 0},
  "to": "socket_id_123"
}
```

```json
{
  "event": "ready-for-connection"
}
```

**Chat**:
```json
{
  "event": "chat-message",
  "text": "Hello everyone!"
}
```

### 6.2 Server → Client Events

**Room Events**:
```json
{
  "event": "room-created",
  "success": true,
  "room": {
    "code": "ABC12345",
    "host": "flutter_1234567890",
    "role": "host"
  }
}
```

```json
{
  "event": "room-joined",
  "success": true,
  "room": {
    "code": "ABC12345",
    "role": "viewer"
  }
}
```

```json
{
  "event": "participant-list",
  "participants": [
    {"id": "host_123", "name": "Host", "role": "host"},
    {"id": "viewer_456", "name": "Guest", "role": "viewer"}
  ]
}
```

```json
{
  "event": "participant-joined",
  "id": "viewer_456",
  "name": "Guest"
}
```

```json
{
  "event": "participant-left",
  "id": "viewer_456"
}
```

**Stream Events**:
```json
{
  "event": "torrent-magnet",
  "magnetURI": "magnet:?xt=urn:btih:...",
  "streamPath": "video.mp4",
  "name": "My Movie"
}
```

```json
{
  "event": "movie-loaded",
  "name": "My Movie",
  "duration": 7200.5
}
```

**Playback Sync Events**:
```json
{
  "event": "sync-play",
  "time": 125.5,
  "actionId": "1699999999999"
}
```

```json
{
  "event": "sync-pause",
  "time": 125.5,
  "actionId": "1699999999999"
}
```

```json
{
  "event": "sync-seek",
  "time": 300.0,
  "actionId": "1699999999999"
}
```

```json
{
  "event": "playback-snapshot",
  "playback": {
    "time": 125.5,
    "type": "play"
  }
}
```

**Advanced Sync Events**:
```json
{
  "event": "sync-check",
  "roomCode": "ABC12345",
  "timestamp": 1699999999999
}
```

```json
{
  "event": "sync-report",
  "roomCode": "ABC12345",
  "participantId": "viewer_456",
  "playbackTime": 125.5,
  "playing": true,
  "timestamp": 1699999999999
}
```

```json
{
  "event": "sync-correct",
  "roomCode": "ABC12345",
  "playbackTime": 125.5,
  "playing": true,
  "actionId": "1699999999999"
}
```

**WebRTC Events**:
```json
{
  "event": "start-webrtc",
  "peerId": "socket_id_123",
  "initiator": true
}
```

```json
{
  "event": "offer",
  "from": "socket_id_123",
  "offer": {"type": "offer", "sdp": "..."}
}
```

```json
{
  "event": "answer",
  "from": "socket_id_123",
  "answer": {"type": "answer", "sdp": "..."}
}
```

```json
{
  "event": "ice-candidate",
  "from": "socket_id_123",
  "candidate": {"candidate": "...", "sdpMid": "0", "sdpMLineIndex": 0}
}
```

**Chat Events**:
```json
{
  "event": "chat-message",
  "id": "msg_123",
  "senderId": "viewer_456",
  "sender": "Guest",
  "senderRole": "viewer",
  "text": "Hello!",
  "timestamp": 1699999999999
}
```

**Error Event**:
```json
{
  "event": "error",
  "message": "Room not found"
}
```

## 7. Build Instructions

### 7.1 Go Engine Build Commands

#### Prerequisites
- Go 1.21 or later
- GCC (for CGO)

#### Build for Windows
```bash
cd go/sharestream-engine

# Build for Windows x64
GOOS=windows GOARCH=amd64 CGO_ENABLED=1 go build -o bin/sharestream-engine.exe ./cmd/sharestream-engine

# Or build interactively
go build -o bin/sharestream-engine.exe ./cmd/sharestream-engine
```

#### Build for macOS
```bash
cd go/sharestream-engine

# Build for macOS x64
GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 go build -o bin/sharestream-engine ./cmd/sharestream-engine

# Build for macOS ARM (Apple Silicon)
GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 go build -o bin/sharestream-engine ./cmd/sharestream-engine
```

#### Build for Linux
```bash
cd go/sharestream-engine

# Build for Linux x64
GOOS=linux GOARCH=amd64 CGO_ENABLED=1 go build -o bin/sharestream-engine ./cmd/sharestream-engine

# Build for Linux ARM
GOOS=linux GOARCH=arm64 CGO_ENABLED=1 go build -o bin/sharestream-engine ./cmd/sharestream-engine
```

#### Cross-Compilation Script
```bash
#!/bin/bash
# build-all.sh

set -e

cd "$(dirname "$0")/sharestream-engine"

echo "Building for Windows..."
GOOS=windows GOARCH=amd64 CGO_ENABLED=1 go build -o ../bin/windows-amd64/sharestream-engine.exe ./cmd/sharestream-engine

echo "Building for macOS x64..."
GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 go build -o ../bin/darwin-amd64/sharestream-engine ./cmd/sharestream-engine

echo "Building for macOS ARM..."
GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 go build -o ../bin/darwin-arm64/sharestream-engine ./cmd/sharestream-engine

echo "Building for Linux x64..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=1 go build -o ../bin/linux-amd64/sharestream-engine ./cmd/sharestream-engine

echo "Building for Linux ARM..."
GOOS=linux GOARCH=arm64 CGO_ENABLED=1 go build -o ../bin/linux-arm64/sharestream-engine ./cmd/sharestream-engine

echo "All builds complete!"
```

### 7.2 Signaling Server Deployment

#### Local Development
```bash
cd go/sharestream-signal

# Install dependencies
go mod download

# Run locally
go run ./cmd/main.go -port 3001
```

#### Docker Build
```bash
cd go/sharestream-signal

# Build Docker image
docker build -t sharestream-signal:latest .

# Run locally
docker run -p 3001:3001 sharestream-signal:latest

# With TURN credentials
docker run -p 3001:3001 \
  -e TURN_URL=turn:your-turn-server.com:3478 \
  -e TURN_USER=username \
  -e TURN_PASS=password \
  sharestream-signal:latest
```

#### Koyeb Deployment

1. **Create GitHub Repository**
   ```bash
   # Push code to GitHub
   git init
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/yourusername/sharestream-signal.git
   git push -u main
   ```

2. **Deploy to Koyeb**
   - Log in to [Koyeb](https://koyeb.com)
   - Click "Create App"
   - Select "GitHub" as the source
   - Choose your repository
   - Configure:
     - **Builder**: Docker
     - **Port**: 3001
     - **Environment Variables**:
       - `TURN_URL` (optional): Your TURN server URL
       - `TURN_USER` (optional): TURN username
       - `TURN_PASS` (optional): TURN password
   - Click "Deploy"

3. **Get Your Server URL**
   - After deployment, note your Koyeb app URL (e.g., `https://sharestream-signal-xxx.koyeb.app`)
   - This becomes your `SERVER_URL` in Flutter

### 7.3 Flutter Build Commands

#### Prerequisites
- Flutter SDK 3.x
- Platform-specific tools:
  - Windows: Visual Studio with C++ toolchain
  - macOS: Xcode
  - Linux: GTK development libraries

#### Install Dependencies
```bash
flutter pub get
```

#### Build for Windows
```bash
# Debug build
flutter build windows

# Release build
flutter build windows --release
```

Output: `build/windows/x64/release/bundle/sharestream.exe`

#### Build for macOS
```bash
# Debug build
flutter build macos

# Release build
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/sharestream.app`

#### Build for Linux
```bash
# Debug build
flutter build linux

# Release build
flutter build linux --release
```

Output: `build/linux/x64/release/bundle/sharestream`

#### Build for Web (Optional)
```bash
flutter build web
```

#### Running in Development
```bash
# Run with debug mode
flutter run -d windows
flutter run -d macos
flutter run -d linux

# Or specify a specific device
flutter devices
flutter run -d <device-id>
```

## 8. Runtime Requirements

### 8.1 FFmpeg Requirements

The local HTTP server in `sharestream-engine` uses `Range` requests to support seeking. FFmpeg is **not required** for basic playback if:
- Video files are MP4 with seekable atoms
- HTTP server supports Range requests

**Optional FFmpeg integration** (for transcoding or non-seekable formats):
```bash
# Windows (choco)
choco install ffmpeg

# macOS (brew)
brew install ffmpeg

# Linux (apt)
sudo apt install ffmpeg
```

### 8.2 Minimum System Specs

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **OS** | Windows 10, macOS 11, Ubuntu 20.04 | Latest stable |
| **CPU** | Dual-core 2GHz | Quad-core 3GHz+ |
| **RAM** | 4 GB | 8 GB |
| **Storage** | 500 MB (app only) | 10+ GB for cache |
| **Network** | 10 Mbps | 50+ Mbps |
| **Display** | 1280x720 | 1920x1080 |

### 8.3 Environment Variables

Create a `.env` file in the project root:

```bash
# Server Configuration
SERVER_URL=https://your-signal-server.koyeb.app

# TURN Configuration (optional)
TURN_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your_username
TURN_PASSWORD=your_password

# Development (optional)
DEBUG=true
LOG_LEVEL=debug
```

### 8.4 Port Requirements

| Port | Service | Direction |
|------|---------|-----------|
| 3001 | Signaling Server | Inbound/Outbound |
| 42069 | Engine HTTP Server | Localhost only |
| 6881 | BitTorrent DHT | Inbound/Outbound |
| 6882+ | BitTorrent | Inbound/Outbound |
| 3478 | STUN/TURN | Outbound |
| 443 | TURN (TLS) | Outbound |

## 9. Flutter Integration

### 9.1 Changes to torrent_service.dart

The `TorrentService` class manages the `sharestream-engine` subprocess. Key integration points:

**Location**: `lib/services/torrent_service.dart`

**Process Management**:
- Starts engine as subprocess with `-http-port 42069` argument
- Communicates via stdin (JSON commands)
- Receives events via stdout (JSON events)
- Logs to `${app_support_dir}/torrent.log`

**Key Methods**:
```dart
// Start the engine (called automatically on first seed/download)
Future<bool> start()

// Seed a local file - returns localhost URL for playback
Future<String?> seed(String filePath)

// Download from magnet - returns localhost URL
Future<String?> download(String magnet)

// Stop current torrent
void stop()

// Shutdown engine
Future<void> dispose()
```

**State Notifiers**:
- `isReady` - Engine is ready to accept commands
- `isSeeding` - Currently seeding a file
- `isDownloading` - Currently downloading
- `progress` - Download progress (0.0-1.0)
- `downloadSpeed` - Bytes per second
- `numPeers` - Connected peer count
- `serverUrl` - Local HTTP URL for playback
- `magnetUri` - Generated magnet URI
- `torrentName` - Name of torrent
- `lastError` - Last error message

### 9.2 Changes to socket_service.dart

The `SocketService` class handles Socket.IO communication with the signaling server.

**Location**: `lib/services/socket_service.dart`

**Connection Management**:
```dart
// Connect to signaling server
void connect(String serverUrl)

// Create a new room
void createRoom({String? name, String? requestedCode})

// Join existing room
void joinRoom(String code, {String? name})

// Leave current room
void leaveRoom()
```

**Playback Sync**:
```dart
// Notify play
void syncPlay(double time)

// Notify pause
void syncPause(double time)

// Notify seek
void syncSeek(double time)

// Advanced sync
void sendSyncCheck()
void sendSyncReport(double playbackTime, bool playing)
void sendSyncCorrect(double playbackTime, bool playing)
```

**Stream Sharing**:
```dart
// Share magnet with viewers
void shareMagnet(String magnet, String path, String name)

// Notify movie loaded
void emitMovieLoaded(String name, double duration)
```

**Callbacks**:
```dart
// Playback sync
void Function(double time)? onSeekRequested
void Function(bool playing)? onPlayPauseRequested

// Torrent
void Function(String magnet, String path)? onTorrentMagnet

// Advanced sync
void Function(int timestamp)? onSyncCheck
void Function(String participantId, double time, bool playing)? onSyncReport
void Function(double time, bool playing, String actionId)? onSyncCorrect

// WebRTC
void Function(String peerId, bool initiator)? onStartWebRTC
void Function(String fromId, Map<String, dynamic> offer)? onOffer
void Function(String fromId, Map<String, dynamic> answer)? onAnswer
void Function(String fromId, Map<String, dynamic> candidate)? onIceCandidate
void Function(String peerId)? onPeerLeft
```

### 9.3 Changes to webrtc_service.dart

The `WebRTCService` class manages WebRTC peer connections for video calling.

**Location**: `lib/services/webrtc_service.dart`

**Features**:
- Mesh networking (each participant connects to all others)
- STUN servers (Google's public STUN)
- TURN server support (dynamic loading from environment)
- Audio/video toggle

**Key Methods**:
```dart
// Start video call - requests camera/mic
Future<void> startCall()

// Stop call, close all connections
Future<void> stopCall()

// Toggle audio
void toggleAudio()

// Toggle video
void toggleVideo()

// Add TURN server dynamically
void addTurnServer(String url, String username, String credential)

// Create renderer for displaying remote video
RTCVideoRenderer createRenderer()
```

**State Notifiers**:
- `isInCall` - Currently in a call
- `audioEnabled` - Audio is enabled
- `videoEnabled` - Video is enabled
- `localStream` - Local media stream
- `remoteStreams` - Map of peer ID to remote stream

**ICE Servers Configuration**:
```dart
List<Map<String, dynamic>> _iceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
];
// Plus dynamic TURN servers from environment
```

### 9.4 Platform-Specific Considerations

#### Windows
- Engine path: `.exe` extension required
- Firewall: Allow inbound on ports 6881-6889 for BitTorrent
- Path handling: Use forward slashes in paths

#### macOS
- Engine path: No extension (or `.app` bundle)
- Firewall: Allow incoming connections for BitTorrent
- App Sandbox: May need to request exceptions for network
- Notar for distribution outside Appization: Required Store

#### Linux
- Engine path: No extension
- Firewall: Allow inbound on BitTorrent ports
- Desktop integration: May need .desktop file

## 10. Usage Flow

### 10.1 Host Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOST FLOW                                 │
└─────────────────────────────────────────────────────────────────┘

1. START APP
   │
   ▼
2. CONFIGURE SERVER
   ├── Enter SERVER_URL (e.g., https://sharestream-xxx.koyeb.app)
   └── Optional: Configure TURN server
   │
   ▼
3. START ENGINE
   ├── TorrentService.start()
   ├── Engine spawns
   ├── Engine initializes DHT
   └── Engine emits "ready" event
   │
   ▼
4. SELECT MEDIA
   ├── User selects video file
   └── File picker dialog
   │
   ▼
5. SEED FILE
   ├── TorrentService.seed(filePath)
   ├── Engine creates torrent
   ├── Engine starts DHT with tracker URL
   ├── Engine starts HTTP server on localhost:42069
   ├── Engine emits "seeding" with magnet URI and serverUrl
   │
   ▼
6. CREATE ROOM
   ├── SocketService.connect(SERVER_URL)
   ├── SocketService.createRoom()
   ├── Server creates room, returns code (e.g., "ABC12345")
   │
   ▼
7. SHARE STREAM
   ├── User shares room code with viewers
   ├── Optional: Auto-share magnet when movie loads
   │   ├── Play video
   │   ├── Video triggers "movie-loaded" event
   │   ├── SocketService.emitMovieLoaded()
   │   └── SocketService.shareMagnet(magnet, path, name)
   │
   ▼
8. VIDEO CALL (Optional)
   ├── User clicks "Start Video Call"
   ├── WebRTCService.startCall()
   ├── SocketService emits "ready-for-connection"
   ├── WebRTC mesh forms with all participants
   │
   ▼
9. PLAYBACK CONTROL
   ├── Play/Pause/Seek events
   ├── SocketService.syncPlay/Pause/Seek()
   ├── Server broadcasts to all viewers
   │
   ▼
10. END STREAM
    ├── User stops video or leaves room
    ├── TorrentService.stop()
    ├── SocketService.leaveRoom()
    └── Engine cleans up

```

### 10.2 Viewer Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                       VIEWER FLOW                                │
└─────────────────────────────────────────────────────────────────┘

1. START APP
   │
   ▼
2. CONFIGURE SERVER
   ├── Enter SERVER_URL (provided by host)
   └── Optional: Configure TURN server
   │
   ▼
3. JOIN ROOM
   ├── SocketService.connect(SERVER_URL)
   ├── SocketService.joinRoom(code)
   ├── Server validates and adds participant
   │
   ▼
4. RECEIVE STREAM INFO
   ├── Server emits "torrent-magnet"
   ├── SocketService receives magnet URI
   ├── Optional: Server sends "movie-loaded" if already playing
   │
   ▼
5. START ENGINE (First viewer only)
   ├── TorrentService.start()
   ├── Engine emits "ready"
   │
   ▼
6. START DOWNLOAD
   ├── TorrentService.download(magnet)
   ├── Engine connects to host (first seeder)
   ├── Engine connects to other peers (DHT)
   ├── Progress updates via "progress" events
   │
   ▼
7. PLAYBACK
   ├── On "done" event or progress > threshold
   ├── Use serverUrl from "seeding" or "added" event
   ├── Pass URL to video player (media_kit)
   ├── Example: http://localhost:42069/video.mp4
   │
   ▼
8. SYNC WITH HOST
   ├── Receive sync events from server
   ├── "sync-play" → start playback at time
   ├── "sync-pause" → pause playback at time
   ├── "sync-seek" → seek to time
   │
   ▼
9. VIDEO CALL (Optional)
   ├── Join host's mesh network
   ├── Receive camera/mic from host and other viewers
   │
   ▼
10. LEAVE ROOM
    ├── SocketService.leaveRoom()
    ├── Optional: TorrentService.stop()
    └── Cleanup

```

### 10.3 Step-by-Step Commands

#### Host Commands
```bash
# 1. Start Flutter app
flutter run -d windows

# 2. In app:
#    - Set SERVER_URL in settings
#    - Click "Host Room"
#    - Select video file
#    - Wait for "seeding" status
#    - Share room code with viewers
#    - Optional: Start video call

# 3. Watch for connections
#    - Progress shows peer count
#    - Can see downloads in engine logs
```

#### Viewer Commands
```bash
# 1. Start Flutter app
flutter run -d windows

# 2. In app:
#    - Set SERVER_URL (same as host)
#    - Enter room code
#    - Wait for magnet URI
#    - Wait for download to start
#    - Play when ready
#    - Playback syncs with host
```

## 11. Troubleshooting

### 11.1 Engine Issues

#### Engine Not Starting
**Symptoms**: `Could not find sharestream-engine` error

**Solutions**:
1. Verify engine binary exists:
   ```bash
   # Windows
   dir go\sharestream-engine\*.exe
   
   # macOS/Linux
   ls go/sharestream-engine/
   ```

2. Check path in `torrent_service.dart`:
   - Ensure path candidates include your build location
   - Try adding full path to candidates list

3. Run engine manually to check for errors:
   ```bash
   # Windows
   .\go\sharestream-engine\sharestream-engine.exe -http-port 42069
   
   # Should see "ready" output
   ```

#### Download Not Starting
**Symptoms**: `added` event received but no progress

**Solutions**:
1. Check tracker URL is correct (must be WebSocket)
2. Verify host has seeds available
3. Check firewall allows outbound connections
4. Try with a small test file first

#### Seeding Not Working
**Symptoms**: `seed` command succeeds but no magnet returned

**Solutions**:
1. Verify file path is absolute and accessible
2. Check file is readable
3. Ensure file is a valid media file

### 11.2 Signaling Server Issues

#### Connection Refused
**Symptoms**: `SocketService` cannot connect to server

**Solutions**:
1. Verify server URL is correct (include `https://`)
2. Check server is deployed and running
3. Test with curl:
   ```bash
   curl https://your-server.koyeb.app/health
   ```
4. Check server logs in Koyeb dashboard

#### Room Not Found
**Symptoms**: `join-room` fails with "Room not found"

**Solutions**:
1. Verify room code is correct (case-sensitive)
2. Check room hasn't expired (no participants for 30 min)
3. Host may need to recreate room

### 11.3 Playback Issues

#### Video Not Playing
**Symptoms**: Player shows error or doesn't start

**Solutions**:
1. Check download progress (needs ~5-10% to start playing)
2. Verify format is supported (MP4, MKV, AVI)
3. Try different media file
4. Check `serverUrl` is correct in player

#### Seeking Not Working
**Symptoms**: Cannot seek in video

**Solutions**:
1. File must have seekable atoms (MP4)
2. Engine must be running
3. Try seeking near downloaded portion first
4. Wait for more download

#### Sync Not Working
**Symptoms**: Viewers out of sync with host

**Solutions**:
1. Check network latency
2. Verify all sync events are being received
3. Try manual sync: click play/pause in host's player
4. Check for conflicting playback controls

### 11.4 WebRTC Issues

#### Video Call Not Connecting
**Symptoms**: `startCall()` fails or no remote video

**Solutions**:
1. Check camera/mic permissions
2. Verify TURN server is configured
3. Check firewall allows STUN/TURN ports
4. Try with both participants on same network

#### Poor Video Quality
**Symptoms**: Frozen or pixelated video

**Solutions**:
1. Check network bandwidth
2. Reduce video resolution in code:
   ```dart
   'video': {'width': {'ideal': 160}, 'height': {'ideal': 120}}
   ```
3. Enable TURN if behind NAT

### 11.5 Network Issues

#### Port Already in Use
**Symptoms**: Engine fails to start HTTP server

**Solutions**:
1. Change port in `torrent_service.dart`:
   ```dart
   Process.start(enginePath, ['-http-port', '42070'])
   ```
2. Or kill process using port:
   ```bash
   # Windows
   netstat -ano | findstr :42069
   taskkill /PID <pid>
   
   # macOS/Linux
   lsof -i :42069
   kill <pid>
   ```

#### Firewall Blocking
**Symptoms**: Cannot connect to peers

**Solutions**:
1. Windows: Allow app through firewall
2. macOS: System Preferences → Security & Privacy → Firewall
3. Linux: `sudo ufw allow 6881:6889/tcp`

### 11.6 Debug Tips

#### Enable Debug Logging
```dart
// In .env file
DEBUG=true
LOG_LEVEL=debug
```

#### Check Engine Logs
```bash
# Location varies by platform
# Windows: %APPDATA%\sharestream\torrent.log
# macOS: ~/Library/Application Support/sharestream/torrent.log
# Linux: ~/.local/share/sharestream/torrent.log
```

#### Test Components Independently

1. Test signaling server:
   ```bash
   curl http://localhost:3001/health
   ```

2. Test engine directly:
   ```bash
   echo '{"cmd":"quit"}' | ./sharestream-engine
   ```

3. Test Socket.IO:
   ```bash
   # Use socket.io tester or browser dev tools
   ```

#### Common Error Codes

| Code | Meaning |
|------|---------|
| E001 | Engine not found |
| E002 | Engine startup timeout |
| E003 | Invalid torrent file |
| E004 | Network error |
| E005 | File access denied |
| S001 | Server connection failed |
| S002 | Room not found |
| S003 | Invalid room code |
| W001 | WebRTC not supported |
| W002 | Camera/mic denied |
| W003 | ICE connection failed |

## Appendix: Quick Reference

### File Locations
| File | Purpose |
|------|---------|
| `go/sharestream-engine/` | P2P torrent engine |
| `go/sharestream-signal/` | Signaling server |
| `lib/services/torrent_service.dart` | Engine IPC |
| `lib/services/socket_service.dart` | Server communication |
| `lib/services/webrtc_service.dart` | Video calls |
| `pubspec.yaml` | Flutter dependencies |

### Environment Variables
| Variable | Required | Default |
|----------|----------|---------|
| `SERVER_URL` | Yes | `http://localhost:3001` |
| `TURN_URL` | No | - |
| `TURN_USERNAME` | No | - |
| `TURN_PASSWORD` | No | - |

### Default Ports
| Port | Service |
|------|---------|
| 3001 | Signaling server |
| 42069 | Engine HTTP |
| 6881-6889 | BitTorrent |

### Key Events
- Engine: `ready`, `seeding`, `added`, `progress`, `done`, `stopped`, `error`
- Socket: `sync-play`, `sync-pause`, `sync-seek`, `torrent-magnet`
- WebRTC: `start-webrtc`, `offer`, `answer`, `ice-candidate`
