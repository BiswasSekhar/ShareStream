# ShareStream Architecture

## System Overview

ShareStream is a **decentralized video streaming platform** combining P2P torrent distribution with WebRTC video calling. The system consists of three main components working together to provide synchronized video watching with real-time communication.

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SHARESTREAM SYSTEM                                │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────┐      WebSocket       ┌─────────────────────┐
│   sharestream-      │◄────────────────────►│   sharestream-      │
│   signal            │    Socket.IO v4      │   signal            │
│   (Go Server)       │                      │   (Cloud/Remote)    │
│   Port: 3001        │                      │   Koyeb/AWS/etc     │
└──────────┬──────────┘                      └─────────────────────┘
           │
           │ WebSocket
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
┌─────────┐  ┌─────────┐
│  Host   │  │ Viewer  │
│ Flutter │  │ Flutter │
└────┬────┘  └────┬────┘
     │            │
     ▼            ▼
┌─────────┐  ┌─────────┐
│ Torrent │  │ Torrent │
│ Engine  │  │ Engine  │
│ (Local) │  │ (Local) │
└────┬────┘  └────┬────┘
     │   P2P      │
     │ BitTorrent │
     └────────────┘
```

## Component Details

### 1. Flutter Desktop Application

**Purpose**: User interface for hosting and viewing streams

**Key Features**:
- Room creation and management
- Video playback with media_kit
- WebRTC video calling
- Real-time chat
- Playback synchronization

**Architecture Pattern**:
```
┌─────────────────────────────────────────┐
│           Flutter Application           │
├─────────────────────────────────────────┤
│  UI Layer (Screens + Widgets)           │
│  ├─ home_screen.dart (Landing)          │
│  ├─ room_screen.dart (Video room)       │
│  └─ widgets/ (Reusable components)      │
├─────────────────────────────────────────┤
│  Provider Layer (State Management)      │
│  └─ room_provider.dart                  │
├─────────────────────────────────────────┤
│  Service Layer                          │
│  ├─ torrent_service.dart (P2P engine)   │
│  ├─ socket_service.dart (Signaling)     │
│  └─ webrtc_service.dart (Video calls)   │
├─────────────────────────────────────────┤
│  Native Layer (Platform channels)       │
│  └─ media_kit, flutter_webrtc           │
└─────────────────────────────────────────┘
```

### 2. ShareStream-Engine (Local P2P)

**Purpose**: BitTorrent client for video distribution

**Technology Stack**:
- Language: Go 1.21+
- BitTorrent: anacrolix/torrent library
- IPC: JSON over stdin/stdout
- HTTP: Range request streaming server

**Key Capabilities**:
```
┌─────────────────────────────────────────┐
│         TorrentEngine                   │
├─────────────────────────────────────────┤
│  Seeding                                │
│  ├─ Create torrent from local file      │
│  ├─ Generate magnet URI                 │
│  └─ Serve via HTTP                      │
├─────────────────────────────────────────┤
│  Downloading                            │
│  ├─ Add magnet URI                      │
│  ├─ Download from peers                 │
│  └─ Stream while downloading            │
├─────────────────────────────────────────┤
│  HTTP Server                            │
│  ├─ Range request support (seeking)     │
│  └─ Auto-assigned port (default :42069) │
└─────────────────────────────────────────┘
```

**Data Flow**:
1. Host selects video file
2. Engine creates torrent and starts seeding
3. Engine returns magnet URI + local HTTP URL
4. Flutter plays from local HTTP URL
5. Magnet URI shared with viewers via signal server
6. Viewer engines download via P2P
7. Viewers play from their local HTTP servers

### 3. ShareStream-Signal (Signaling Server)

**Purpose**: Central coordination for room management and WebRTC signaling

**Technology Stack**:
- Language: Go 1.21+
- WebSocket: Socket.IO v4 (zishang520)
- HTTP: Gorilla Mux router
- TURN: Optional static credentials

**Responsibilities**:
```
┌─────────────────────────────────────────┐
│         Signal Server                   │
├─────────────────────────────────────────┤
│  Room Management                        │
│  ├─ Create room with unique code        │
│  ├─ Join room by code                   │
│  ├─ Track participants                  │
│  └─ Join approval workflow              │
├─────────────────────────────────────────┤
│  Playback Synchronization               │
│  ├─ sync-play (broadcast)               │
│  ├─ sync-pause (broadcast)              │
│  ├─ sync-seek (broadcast)               │
│  └─ sync-check/report/correct           │
├─────────────────────────────────────────┤
│  WebRTC Signaling                       │
│  ├─ start-webrtc                        │
│  ├─ offer/answer relay                  │
│  └─ ice-candidate relay                 │
├─────────────────────────────────────────┤
│  Chat                                   │
│  └─ Broadcast messages to room          │
└─────────────────────────────────────────┘
```

## Data Flows

### Host Flow (Creating a Stream)

```
1. User opens app
   │
   ▼
2. Click "Host Room"
   │
   ▼
3. Flutter: socket.connect(SERVER_URL)
   │
   ▼
4. Flutter: socket.emit('create-room')
   │
   ▼
5. Server: Create room, return room code
   │
   ▼
6. User selects video file
   │
   ▼
7. Flutter: torrentService.seed(filePath)
   │
   ▼
8. Engine: Create torrent, start seeding
   │
   ▼
9. Engine: Return magnet URI + HTTP URL
   │
   ▼
10. Flutter: Play video from HTTP URL
    │
    ▼
11. Flutter: socket.emit('torrent-magnet', magnet)
    │
    ▼
12. Server: Broadcast magnet to all viewers
```

### Viewer Flow (Joining a Stream)

```
1. User enters room code, clicks "Join"
   │
   ▼
2. Flutter: socket.connect(SERVER_URL)
   │
   ▼
3. Flutter: socket.emit('join-request')
   │
   ▼
4. Server: Notify host of join request
   │
   ▼
5. Host approves (via dialog)
   │
   ▼
6. Server: Emit 'join-approved' to viewer
   │
   ▼
7. Flutter: socket.emit('join-room')
   │
   ▼
8. Server: Add to room, notify participants
   │
   ▼
9. Server: Emit 'torrent-magnet' to new viewer
   │
   ▼
10. Flutter: torrentService.download(magnet)
    │
    ▼
11. Engine: Start downloading torrent
    │
    ▼
12. Engine: When ready, return HTTP URL
    │
    ▼
13. Flutter: Play video from HTTP URL
    │
    ▼
14. Receive sync events from host
```

### WebRTC Flow (Video Calling)

```
1. User clicks "Start Video Call"
   │
   ▼
2. Flutter: webrtcService.startCall()
   │   ├─ Get user media (camera/mic)
   │   └─ Create peer connections
   │
   ▼
3. Flutter: socket.emit('ready-for-connection')
   │
   ▼
4. Server: Notify all peers in room
   │
   ▼
5. Each peer: socket.emit('start-webrtc', ...)
   │
   ▼
6. WebRTC: Exchange offers/answers
   │   ├─ Peer A creates offer
   │   ├─ Server relays to Peer B
   │   ├─ Peer B creates answer
   │   └─ Server relays to Peer A
   │
   ▼
7. WebRTC: Exchange ICE candidates
   │
   ▼
8. Connection established
   │
   ▼
9. Media streams flow P2P (mesh topology)
```

## Network Architecture

### Ports Used

| Port | Protocol | Purpose |
|------|----------|---------|
| 3001 | HTTP/WebSocket | Signaling server |
| 42069 | HTTP | Engine streaming (localhost only) |
| 6881-6889 | TCP/UDP | BitTorrent DHT and peer connections |
| 3478 | UDP | STUN/TURN (if configured) |

### WebRTC Mesh Network

```
          ┌─────────┐
          │  Host   │
          └────┬────┘
               │
       ┌───────┼───────┐
       │       │       │
       ▼       ▼       ▼
  ┌────────┐┌────────┐┌────────┐
  │Viewer 1││Viewer 2││Viewer 3│
  └────┬───┘└────┬───┘└────┬───┘
       │         │         │
       └─────────┼─────────┘
                 │
            P2P Connections
       (Each peer connects to all others)
```

**Note**: This is a full mesh topology. For N participants, each sends their video to N-1 peers. Bandwidth scales O(N²).

## Security Considerations

1. **Room Codes**: Random 6-8 character alphanumeric codes
2. **Join Approval**: Host must approve viewers before they can join
3. **TURN Server**: Optional for NAT traversal in WebRTC
4. **Local HTTP**: Engine only binds to localhost (127.0.0.1)
5. **No Encryption**: BitTorrent traffic is unencrypted by default

## Scalability Limits

| Component | Limit | Notes |
|-----------|-------|-------|
| WebRTC Mesh | ~4-6 peers | Bandwidth constraint |
| BitTorrent | 100+ peers | Depends on upload bandwidth |
| Rooms | Unlimited | Server memory constraint |
| Video Quality | 1080p max | Limited by peer upload |

## Technology Choices

### Why BitTorrent for Video?
- **Decentralized**: No central video server needed
- **Efficient**: Viewers share bandwidth with each other
- **Resumable**: Can pause/resume downloads
- **Proven**: Battle-tested protocol

### Why WebRTC Mesh?
- **Simple**: No SFU/MCU server needed
- **Low Latency**: Direct peer connections
- **Sufficient**: Designed for small watch parties (2-6 people)

### Why Socket.IO?
- **Reliable**: Auto-reconnection, fallbacks
- **Simple**: Event-based API
- **Compatible**: Works with Flutter web socket client

## Future Considerations

1. **Selective Forwarding Unit (SFU)**: For larger groups (>6 people)
2. **WebTorrent**: Browser-based torrent for web client
3. **End-to-End Encryption**: Encrypt video content
4. **Recording**: Server-side recording option
