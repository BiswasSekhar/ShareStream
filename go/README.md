# ShareStream Go Backend

This directory contains the Go-based backend implementation for ShareStream, providing a drop-in replacement for the Node.js torrent-bridge.

## Directory Structure

```
go/
├── sharestream-engine/       # Local P2P streaming engine
│   ├── cmd/main.go          # Entry point
│   ├── internal/
│   │   ├── engine/          # Torrent client (anacrolix/torrent)
│   │   ├── http/            # HTTP server with Range requests
│   │   ├── ipc/             # JSON IPC bridge (stdin/stdout)
│   │   ├── transcode/       # FFmpeg transcoding pipeline
│   │   └── webrtc/          # WebRTC peer connections
│   ├── build.sh             # Unix build script
│   └── build.bat            # Windows build script
│
├── sharestream-signal/       # Signaling server
│   ├── cmd/main.go          # Entry point
│   ├── internal/
│   │   ├── server/          # Socket.IO server setup
│   │   ├── handlers/        # Event handlers
│   │   ├── sync/            # Playback sync manager
│   │   └── turn/            # TURN credential generator
│   ├── build.sh             # Unix build script
│   ├── build.bat            # Windows build script
│   └── Dockerfile           # Koyeb deployment
│
└── bin/                     # Build output (generated)
```

## sharestream-engine

The local P2P streaming engine that replaces the Node.js sidecar.

### Features

- **BitTorrent Integration**: Uses anacrolix/torrent for seeding and downloading
- **HTTP Streaming**: Serves media files with Range request support for media_kit playback
- **IPC Protocol**: JSON-based stdin/stdout communication (compatible with Flutter TorrentService)
- **FFmpeg Transcoding**: Auto-detects format and transcodes if needed
- **WebRTC Support**: Built-in WebRTC peer connection support

### Commands

The engine accepts these JSON commands via stdin:

| Command | Description |
|---------|-------------|
| `{"cmd":"seed","filePath":"/path/to/file","trackerUrl":"ws://..."}` | Seed a local file |
| `{"cmd":"add","magnetURI":"magnet:...","trackerUrl":"ws://..."}` | Add magnet link |
| `{"cmd":"stop"}` | Stop current torrent |
| `{"cmd":"info"}` | Get torrent info |
| `{"cmd":"quit"}` | Quit the engine |

### Events

The engine outputs these JSON events via stdout:

| Event | Description |
|-------|-------------|
| `{"event":"ready"}` | Engine is ready |
| `{"event":"seeding","serverUrl":"...","magnetURI":"...","name":"..."}` | Seeding started |
| `{"event":"added","serverUrl":"...","name":"..."}` | Magnet added |
| `{"event":"progress","downloaded":0.5,"speed":1000000,"peers":5}` | Download progress |
| `{"event":"done"}` | Download complete |
| `{"event":"stopped"}` | Torrent stopped |
| `{"event":"error","message":"..."}` | Error occurred |

### Building

```bash
# Unix
cd sharestream-engine
./build.sh

# Windows
cd sharestream-engine
build.bat
```

### Usage

```bash
./sharestream-engine -http-port 42069 -data-dir ~/.sharestream
```

## sharestream-signal

The signaling server for room management and WebRTC signaling.

### Features

- **Socket.IO v4**: Real-time bidirectional communication
- **Room Management**: Create/join rooms with auto-generated codes
- **Playback Sync**: Periodic timestamp synchronization (15s interval)
- **TURN Credentials**: Cloudflare TURN credential generation
- **WebRTC Signaling**: Peer connection establishment

### Events Handled

| Event | Description |
|-------|-------------|
| `create-room` | Create a new room |
| `join-room` | Join an existing room |
| `leave-room` | Leave current room |
| `torrent-magnet` | Share magnet URI |
| `movie-loaded` | Notify movie loaded |
| `sync-play/pause/seek` | Playback sync |
| `sync-check` | Request sync check |
| `sync-report` | Report playback state |
| `sync-correct` | Correct playback state |
| `start-webrtc/offer/answer/ice-candidate` | WebRTC signaling |

### Building

```bash
# Unix
cd sharestream-signal
./build.sh

# Windows
cd sharestream-signal
build.bat
```

### Deployment (Koyeb)

1. Build the Docker image:
   ```bash
   docker build -t sharestream-signal ./sharestream-signal
   ```

2. Deploy to Koyeb using the Dockerfile

3. Set environment variables:
   - `PORT=3001`
   - (Optional) TURN server configuration

### Running Locally

```bash
./sharestream-signal -port 3001
```

## Flutter Integration

### Updated Services

1. **torrent_service.dart**: Updated to call Go binary instead of Node.js
2. **socket_service.dart**: Added sync event handlers (sync-check, sync-report, sync-correct)
3. **webrtc_service.dart**: Added TURN server configuration from environment variables

### Environment Variables

```env
SERVER_URL=https://your-server.koyeb.app

# Optional: TURN server (uses Cloudflare TURN if not set)
TURN_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your-username
TURN_CREDENTIAL=your-password
```

## Platform Support

| Platform | Architecture | Build Command |
|----------|--------------|---------------|
| Windows | amd64 | `GOOS=windows GOARCH=amd64 go build` |
| macOS | amd64, arm64 | `GOOS=darwin GOARCH=amd64 go build` |
| Linux | amd64 | `GOOS=linux GOARCH=amd64 go build` |
| Android | arm64 | Cross-compile with NDK |

## Protocol Compatibility

The Go engine is designed to be a drop-in replacement for the Node.js torrent-bridge:

- Same JSON command format
- Same event format
- Same HTTP server port (42069)
- Same torrent tracking (WebSocket tracker)

## License

MIT
