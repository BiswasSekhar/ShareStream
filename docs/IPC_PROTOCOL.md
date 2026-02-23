# ShareStream Engine IPC Protocol

JSON-based IPC protocol for communication between Flutter app and sharestream-engine (Go binary).

## Transport

- **Input**: Flutter writes JSON commands to engine's `stdin`
- **Output**: Engine writes JSON events to `stdout`
- **Encoding**: UTF-8, newline-delimited (`\n`)
- **Format**: One JSON object per line

## Commands (Flutter → Engine)

### seed
Create a torrent from a local file and start seeding.

**Request**:
```json
{
  "cmd": "seed",
  "filePath": "/path/to/video.mp4",
  "trackerUrl": "ws://localhost:3001/"
}
```

**Fields**:
- `cmd` (string, required): `"seed"`
- `filePath` (string, required): Absolute path to video file
- `trackerUrl` (string, optional): WebSocket URL for DHT bootstrap

**Success Response** (`seeding` event):
```json
{
  "event": "seeding",
  "name": "video.mp4",
  "magnetURI": "magnet:?xt=urn:btih:...",
  "serverUrl": "http://localhost:42069/{infohash}"
}
```

**Error Response** (`error` event):
```json
{
  "event": "error",
  "message": "Failed to open file: permission denied"
}
```

---

### add
Download a torrent from a magnet URI.

**Request**:
```json
{
  "cmd": "add",
  "magnetURI": "magnet:?xt=urn:btih:...",
  "trackerUrl": "ws://localhost:3001/"
}
```

**Fields**:
- `cmd` (string, required): `"add"`
- `magnetURI` (string, required): Magnet link with info hash
- `trackerUrl` (string, optional): WebSocket URL for DHT bootstrap

**Success Response** (`added` event):
```json
{
  "event": "added",
  "name": "video.mp4",
  "serverUrl": "http://localhost:42069/{infohash}"
}
```

---

### stop
Stop the current torrent (both seeding and downloading).

**Request**:
```json
{
  "cmd": "stop"
}
```

**Response** (`stopped` event):
```json
{
  "event": "stopped"
}
```

---

### quit
Shutdown the engine process gracefully.

**Request**:
```json
{
  "cmd": "quit"
}
```

**Response**: Process exits with code 0

---

### info
Get current engine status information.

**Request**:
```json
{
  "cmd": "info"
}
```

**Response** (`info` event):
```json
{
  "event": "info",
  "name": "video.mp4",
  "serverUrl": "http://localhost:42069/{infohash}",
  "downloaded": 0.45,
  "peers": 5,
  "speed": 1500000
}
```

## Events (Engine → Flutter)

### ready
Engine is initialized and ready to accept commands.

**Payload**:
```json
{
  "event": "ready",
  "port": 42069
}
```

**Fields**:
- `port` (number): HTTP server port

**Timing**: Sent immediately after engine starts, before processing commands.

---

### seeding
Torrent created and seeding has started.

**Payload**:
```json
{
  "event": "seeding",
  "name": "video.mp4",
  "magnetURI": "magnet:?xt=urn:btih:abc123...",
  "serverUrl": "http://localhost:42069/abc123"
}
```

**Fields**:
- `name` (string): File name
- `magnetURI` (string): Magnet link for sharing
- `serverUrl` (string): Local HTTP URL for playback

---

### added
Magnet URI accepted and download has started.

**Payload**:
```json
{
  "event": "added",
  "name": "video.mp4",
  "serverUrl": "http://localhost:42069/abc123"
}
```

**Fields**:
- `name` (string): Torrent name (from magnet)
- `serverUrl` (string): Local HTTP URL for playback

---

### progress
Periodic progress update (sent every second during active transfers).

**Payload**:
```json
{
  "event": "progress",
  "name": "video.mp4",
  "downloaded": 0.45,
  "speed": 1500000,
  "peers": 5
}
```

**Fields**:
- `name` (string): Torrent name
- `downloaded` (float): Progress ratio (0.0 - 1.0)
- `speed` (integer): Download speed in bytes/second
- `peers` (integer): Number of connected peers

---

### done
Download completed (100% downloaded).

**Payload**:
```json
{
  "event": "done",
  "name": "video.mp4"
}
```

---

### stopped
Torrent has been stopped.

**Payload**:
```json
{
  "event": "stopped"
}
```

---

### error
Error occurred during operation.

**Payload**:
```json
{
  "event": "error",
  "message": "Failed to open file: no such file or directory"
}
```

**Common Error Messages**:
- `"Could not find sharestream-engine"` - Engine binary not found
- `"Engine startup timeout"` - Engine failed to start within 10 seconds
- `"Failed to open file"` - File access error
- `"Invalid magnet URI"` - Malformed magnet link
- `"Network error"` - Connection issues
- `"File access denied"` - Permission error

---

### info
Information/status response (in response to `info` command or periodic).

**Payload**:
```json
{
  "event": "info",
  "serverUrl": "http://localhost:42069/abc123",
  "name": "video.mp4",
  "downloaded": 0.45,
  "peers": 5,
  "speed": 1500000
}
```

## State Machine

```
                    ┌─────────┐
                    │  START  │
                    └────┬────┘
                         │
                         ▼
                    ┌─────────┐
         ┌─────────│  IDLE   │◄────────┐
         │         └────┬────┘         │
         │              │              │
    quit │         seed │ add          │ stop
         │              │              │
         │              ▼              │
         │    ┌─────────────────┐      │
         │    │    SEEDING      │      │
         │    │  / DOWNLOADING  │──────┘
         │    └─────────────────┘
         │              │
         │              │ done
         │              ▼
         │    ┌─────────────────┐
         └───►│  COMPLETED      │
              │  (still seeding)│
              └─────────────────┘
```

## HTTP Streaming

The engine runs an HTTP server for video streaming.

### Endpoints

#### GET /{infohash}
Stream the torrent's video file.

**Supports**:
- Range requests (for seeking)
- Content-Type: application/octet-stream

**Example**:
```bash
# Full file
curl http://localhost:42069/abc123

# Range request
curl -H "Range: bytes=0-1048575" http://localhost:42069/abc123
```

#### GET /stream/{infohash}/{filepath}
Stream a specific file within a multi-file torrent.

#### GET /torrents
List active torrents.

**Response**:
```json
{
  "torrents": ["abc123", "def456"]
}
```

#### GET /torrent/{infohash}
Get detailed torrent information.

**Response**:
```json
{
  "name": "video.mp4",
  "infoHash": "abc123",
  "totalBytes": 1073741824,
  "bytesDone": 536870912,
  "bytesMissing": 536870912,
  "files": [...],
  "numPieces": 4096,
  "complete": false,
  "seeding": true
}
```

## Implementation Notes

### Command Processing
- Commands are processed asynchronously
- Multiple commands can be in flight
- Engine maintains internal state per torrent

### Progress Updates
- Sent every 1 second when active
- Includes name, progress, speed, peers
- Can be used for UI progress bars

### Error Handling
- Errors are non-fatal (engine keeps running)
- Client should handle errors gracefully
- Last error is available via `info` command

### Port Assignment
- Default: Auto-assign (port 0)
- Actual port returned in `ready` event
- HTTP server binds to localhost only (127.0.0.1)

## Example Session

```
# Engine starts
--> {"event": "ready", "port": 42069}

# Flutter requests seed
<-- {"cmd": "seed", "filePath": "/videos/movie.mp4"}
--> {"event": "seeding", "name": "movie.mp4", "magnetURI": "magnet:?xt=urn:btih:abc...", "serverUrl": "http://localhost:42069/abc123"}

# Progress updates (every second)
--> {"event": "progress", "name": "movie.mp4", "downloaded": 1.0, "speed": 0, "peers": 3}

# Flutter stops torrent
<-- {"cmd": "stop"}
--> {"event": "stopped"}

# Flutter quits
<-- {"cmd": "quit"}
[Process exits]
```

## Flutter Integration

See `lib/services/torrent_service.dart` for the Dart implementation.

### Key Methods

```dart
// Start the engine
Future<bool> start()

// Seed a file
Future<String?> seed(String filePath)

// Download from magnet
Future<String?> download(String magnet)

// Stop current torrent
void stop()

// Shutdown engine
Future<void> dispose()
```

### ValueNotifiers

```dart
ValueNotifier<bool> isReady        // Engine ready state
ValueNotifier<bool> isSeeding      // Currently seeding
ValueNotifier<bool> isDownloading  // Currently downloading
ValueNotifier<double> progress     // Download progress (0.0-1.0)
ValueNotifier<int> downloadSpeed   // Bytes/second
ValueNotifier<int> numPeers        // Connected peers
ValueNotifier<String?> serverUrl   // Local HTTP URL
ValueNotifier<String?> magnetUri   // Magnet link
ValueNotifier<String?> torrentName // Current torrent name
ValueNotifier<String?> lastError   // Last error message
```
