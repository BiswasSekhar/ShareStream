# ShareStream REST API

REST API endpoints provided by the signaling server.

## Base URL

```
Local: http://localhost:3001
Production: https://your-server.koyeb.app
```

## Endpoints

### Health Check

Check if the server is running.

**Endpoint**: `GET /health`

**Response**:
```json
{
  "status": "ok"
}
```

**Status Codes**:
- `200 OK`: Server is healthy

---

### Get Tunnel URL

Get the Cloudflare tunnel URL for external access.

**Endpoint**: `GET /api/tunnel`

**Response (tunnel ready)**:
```json
{
  "tunnel": "https://abc123.trycloudflare.com",
  "ready": true
}
```

**Response (tunnel not ready)**:
```json
{
  "tunnel": "",
  "ready": false
}
```

**Status Codes**:
- `200 OK`: Request successful

---

### Get TURN Credentials

Get TURN server credentials for WebRTC.

**Endpoint**: `GET /api/turn/credentials`

**Response**:
```json
{
  "iceServers": [
    {"urls": "stun:stun.l.google.com:19302"},
    {"urls": "stun:stun1.l.google.com:19302"},
    {
      "urls": "turn:your-turn-server.com:3478",
      "username": "user123",
      "credential": "pass456"
    }
  ]
}
```

**Status Codes**:
- `200 OK`: Credentials retrieved

---

### Get Room Info

Get information about a specific room.

**Endpoint**: `GET /api/room/{code}`

**Parameters**:
- `code` (path, required): Room code (e.g., `ABC123`)

**Response (room exists)**:
```json
{
  "code": "ABC123",
  "host": "flutter_1234567890",
  "participants": [
    {
      "id": "flutter_1234567890",
      "name": "Host Name",
      "role": "host"
    },
    {
      "id": "flutter_9876543210",
      "name": "Viewer Name",
      "role": "viewer"
    }
  ]
}
```

**Response (room not found)**:
```json
{
  "error": "Room not found"
}
```

**Status Codes**:
- `200 OK`: Room found
- `404 Not Found`: Room doesn't exist

---

### Join Room (Web)

Web endpoint for joining a room via browser.

**Endpoint**: `GET /join/{code}`

**Parameters**:
- `code` (path, required): Room code

**Response**:
```json
{
  "code": "ABC123",
  "host": "flutter_1234567890",
  "tunnel": "https://abc123.trycloudflare.com"
}
```

---

### Get Ready Count

Get the number of viewers ready to start playback.

**Endpoint**: `GET /api/room/{code}/ready`

**Parameters**:
- `code` (path, required): Room code

**Response**:
```json
{
  "readyCount": 3
}
```

**Status Codes**:
- `200 OK`: Success
- `404 Not Found`: Room doesn't exist

## Engine HTTP API

The local torrent engine also exposes an HTTP server (default: localhost:42069).

### Stream Video

Stream video file from torrent.

**Endpoint**: `GET /{infohash}`

**Parameters**:
- `infohash` (path, required): Torrent info hash

**Headers**:
- `Range` (optional): Byte range for seeking (e.g., `bytes=0-1048575`)

**Response**:
- `200 OK`: Full file
- `206 Partial Content`: Range response
- `404 Not Found`: Torrent not found

**Example**:
```bash
# Full file
curl http://localhost:42069/abc123

# Range request for seeking
curl -H "Range: bytes=0-1048575" http://localhost:42069/abc123
```

---

### List Torrents

List all active torrents.

**Endpoint**: `GET /torrents`

**Response**:
```json
{
  "torrents": ["abc123", "def456"]
}
```

---

### Get Torrent Info

Get detailed information about a torrent.

**Endpoint**: `GET /torrent/{infohash}`

**Parameters**:
- `infohash` (path, required): Torrent info hash

**Response**:
```json
{
  "name": "video.mp4",
  "infoHash": "abc123",
  "totalBytes": 1073741824,
  "bytesDone": 536870912,
  "bytesMissing": 536870912,
  "files": [
    {
      "path": "video.mp4",
      "length": 1073741824,
      "completed": 536870912
    }
  ],
  "numPieces": 4096,
  "complete": false,
  "seeding": true
}
```

## Error Responses

All endpoints return JSON error responses:

```json
{
  "error": "Error description"
}
```

Common HTTP status codes:
- `400 Bad Request`: Invalid parameters
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error

## Rate Limiting

Currently no rate limiting is implemented. For production deployment, consider adding:

```go
// Example middleware
func rateLimit(next http.Handler) http.Handler {
    limiter := rate.NewLimiter(rate.Limit(10), 100)
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if !limiter.Allow() {
            http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
            return
        }
        next.ServeHTTP(w, r)
    })
}
```

## CORS

The server includes CORS headers for all responses:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

## API Versioning

Current API version: **v1** (implicit)

Future versions will use URL prefix:
- `/api/v1/...` (current)
- `/api/v2/...` (future)
