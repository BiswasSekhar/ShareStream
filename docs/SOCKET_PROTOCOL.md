# ShareStream Socket.IO Protocol

Complete reference for Socket.IO events used in ShareStream.

## Connection

### Client → Server
```javascript
// Connect with options
io(SERVER_URL, {
  transports: ['websocket'],
  autoConnect: true,
  reconnection: true,
  reconnectionDelay: 1000,
  reconnectionAttempts: 10
})
```

## Room Management Events

### create-room
**Direction**: Client → Server

Create a new streaming room.

**Payload**:
```json
{
  "participantId": "flutter_1234567890",
  "name": "Host Name",
  "capabilities": {"nativePlayback": true},
  "requestedCode": "CUSTOM01"
}
```

**Fields**:
- `participantId` (string): Unique client identifier
- `name` (string): Display name
- `capabilities` (object): Client capabilities
- `requestedCode` (string, optional): Custom room code

---

### room-created
**Direction**: Server → Client

Confirmation of room creation.

**Payload**:
```json
{
  "success": true,
  "room": {
    "code": "ABC12345",
    "host": "flutter_1234567890",
    "role": "host",
    "tunnel": "https://xxx.trycloudflare.com",
    "inviteToken": "<signed-token>"
  }
}
```

---

### join-room
**Direction**: Client → Server

Join an existing room (requires prior approval).

**Payload**:
```json
{
  "code": "ABC12345",
  "participantId": "flutter_1234567890",
  "name": "Viewer Name",
  "capabilities": {"nativePlayback": true}
}
```

---

### room-joined
**Direction**: Server → Client

Confirmation of room join.

**Payload**:
```json
{
  "success": true,
  "room": {
    "code": "ABC12345",
    "role": "viewer"
  }
}
```

Error response:
```json
{
  "success": false,
  "error": "room not found",
  "requiresApproval": true
}
```

---

### join-request
**Direction**: Client → Server

Request to join a room (requires host approval).

**Payload**:
```json
{
  "code": "ABC12345",
  "participantId": "flutter_1234567890",
  "name": "Viewer Name",
  "inviteToken": "<signed-token>"
}
```

---

### join-approved
**Direction**: Server → Client

Notification that join request was approved.

**Payload**:
```json
{
  "code": "ABC12345"
}
```

---

### join-rejected
**Direction**: Server → Client

Notification that join request was rejected.

**Payload**: Empty object `{}`

---

### join-approve / join-reject
**Direction**: Host Client → Server

Host approves or rejects a pending join request.

**Payload**:
```json
{
  "participantId": "flutter_1234567890",
  "code": "ABC12345"
}
```

---

### leave-room
**Direction**: Client → Server

Leave the current room.

**Payload**: Empty or `{"code": "ABC12345"}`

---

### participant-joined
**Direction**: Server → Client (Broadcast)

Notification when a new participant joins.

**Payload**:
```json
{
  "id": "flutter_1234567890",
  "name": "Viewer Name"
}
```

---

### participant-left
**Direction**: Server → Client (Broadcast)

Notification when a participant leaves.

**Payload**:
```json
{
  "id": "flutter_1234567890"
}
```

---

### participant-list
**Direction**: Server → Client

List of all participants in the room.

**Payload**:
```json
{
  "participants": [
    {"id": "host_123", "name": "Host", "role": "host"},
    {"id": "viewer_456", "name": "Guest", "role": "viewer"}
  ]
}
```

---

### register-participant
**Direction**: Client → Server

Register a participant ID for targeted messaging.

**Payload**:
```json
{
  "participantId": "flutter_1234567890"
}
```

## Stream Events

### torrent-magnet
**Direction**: Bidirectional

Share torrent magnet URI with room.

**Payload**:
```json
{
  "magnetURI": "magnet:?xt=urn:btih:...",
  "streamPath": "video.mp4",
  "name": "Movie Name"
}
```

---

### movie-loaded
**Direction**: Bidirectional

Notify that movie is loaded and ready to play.

**Payload**:
```json
{
  "name": "Movie Name",
  "duration": 7200.5
}
```

---

### room-mode
**Direction**: Server → Client

Notify about room mode changes.

**Payload**:
```json
{
  "mode": "waiting|playing|paused"
}
```

## Playback Sync Events

### control-request
**Direction**: Any Participant → Server

Participant requests playback control operation.

**Payload**:
```json
{
  "code": "ABC12345",
  "participantId": "flutter_1234567890",
  "actionId": "flutter_123_1700000000000",
  "actionType": "play|pause|seek",
  "targetTimeSec": 125.5,
  "playWhenReady": true,
  "baseSeq": 12,
  "sentAtMs": 1700000000000
}
```

---

### control-committed
**Direction**: Server → Room Broadcast

Server-authoritative ordered playback event (strict last-write-wins by sequence).

**Payload**:
```json
{
  "serverSeq": 13,
  "actionId": "flutter_123_1700000000000",
  "actionType": "play|pause|seek",
  "targetTimeSec": 125.5,
  "playWhenReady": true,
  "initiatorParticipantId": "flutter_1234567890",
  "serverCommitMs": 1700000000022
}
```

---

### control-ack
**Direction**: Participant → Server → Host

Acknowledges client-applied control event for drift diagnostics.

**Payload**:
```json
{
  "code": "ABC12345",
  "serverSeq": 13,
  "participantId": "flutter_1234567890",
  "currentTimeSec": 125.7,
  "playing": true,
  "bufferedSec": 22.1,
  "sentAtMs": 1700000000100
}
```

---

### playback-snapshot
**Direction**: Server → Client

Send current playback state to new joiners.

**Payload**:
```json
{
  "serverSeq": 13,
  "playback": {
    "serverSeq": 13,
    "time": 125.5,
    "type": "play|pause"
  }
}
```

## Advanced Sync Events

### sync-check
**Direction**: Host → Server → Broadcast

Request playback position reports from all viewers.

**Payload**:
```json
{
  "roomCode": "ABC12345",
  "timestamp": 1699999999999
}
```

---

### sync-report
**Direction**: Viewer → Server → Host

Viewer reports current playback position.

**Payload**:
```json
{
  "roomCode": "ABC12345",
  "participantId": "viewer_456",
  "playbackTime": 125.5,
  "playing": true,
  "timestamp": 1699999999999
}
```

---

### sync-correct
**Direction**: Host → Server → Target Viewer

Host requests viewer to correct playback position.

**Payload**:
```json
{
  "roomCode": "ABC12345",
  "playbackTime": 125.5,
  "playing": true,
  "actionId": "1699999999999"
}
```

---

### sync-update
**Direction**: Bidirectional

General playback state update.

**Payload**:
```json
{
  "code": "ABC12345",
  "time": 125.5,
  "playing": true,
  "timestamp": 1699999999999
}
```

## Playback Readiness Events

### ready-to-start
**Direction**: Viewer → Server

Viewer is ready to start playback.

**Payload**:
```json
{
  "code": "ABC12345"
}
```

---

### ready-count-update
**Direction**: Server → Host

Update on how many viewers are ready.

**Payload**:
```json
{
  "readyCount": 3
}
```

---

### start-playback
**Direction**: Host → Server → Broadcast

Host starts playback for all viewers.

**Payload**:
```json
{
  "code": "ABC12345"
}
```

---

### playback-started
**Direction**: Server → Client (Broadcast)

Notification that playback has started.

**Payload**:
```json
{
  "hostId": "socket_id_123"
}
```

## WebRTC Signaling Events

### start-webrtc
**Direction**: Bidirectional

Initiate WebRTC connection with a peer.

**Payload**:
```json
{
  "peerId": "socket_id_123",
  "initiator": true
}
```

---

### ready-for-connection
**Direction**: Client → Server

Notify that client is ready for WebRTC connections.

**Payload**: Empty object `{}`

---

### offer
**Direction**: Bidirectional (via relay)

WebRTC session description offer.

**Payload**:
```json
{
  "offer": {
    "type": "offer",
    "sdp": "v=0\r\no=- ..."
  },
  "to": "socket_id_123"
}
```

**Relay Response**:
```json
{
  "from": "socket_id_123",
  "offer": {
    "type": "offer",
    "sdp": "v=0\r\no=- ..."
  }
}
```

---

### answer
**Direction**: Bidirectional (via relay)

WebRTC session description answer.

**Payload**:
```json
{
  "answer": {
    "type": "answer",
    "sdp": "v=0\r\no=- ..."
  },
  "to": "socket_id_123"
}
```

**Relay Response**:
```json
{
  "from": "socket_id_123",
  "answer": {
    "type": "answer",
    "sdp": "v=0\r\no=- ..."
  }
}
```

---

### ice-candidate
**Direction**: Bidirectional (via relay)

WebRTC ICE candidate.

**Payload**:
```json
{
  "candidate": {
    "candidate": "candidate:...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  },
  "to": "socket_id_123"
}
```

**Relay Response**:
```json
{
  "from": "socket_id_123",
  "candidate": {
    "candidate": "candidate:...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  }
}
```

## Chat Events

### chat-message
**Direction**: Bidirectional

Send/receive chat messages.

**Payload (Client → Server)**:
```json
{
  "text": "Hello everyone!",
  "id": "flutter_123_1699999999999",
  "senderId": "flutter_123",
  "sender": "User Name",
  "senderRole": "host",
  "timestamp": 1699999999999
}
```

**Payload (Server → Client)**:
```json
{
  "id": "msg_123",
  "senderId": "viewer_456",
  "sender": "User Name",
  "senderRole": "viewer",
  "text": "Hello everyone!",
  "timestamp": 1699999999999
}
```

## Error Events

### error
**Direction**: Server → Client

General error notification.

**Payload**:
```json
{
  "message": "Room not found"
}
```

Common error messages:
- `"Room not found"` - Invalid room code
- `"use join-request event to join"` - Tried to join without approval
- `"invalid request"` - Malformed request data

## Event Summary Table

| Event | Direction | Purpose |
|-------|-----------|---------|
| create-room | C→S | Create new room |
| room-created | S→C | Room creation confirmation |
| join-room | C→S | Join existing room |
| room-joined | S→C | Join confirmation |
| join-request | C→S | Request to join |
| join-approved | S→C | Approval notification |
| join-rejected | S→C | Rejection notification |
| join-approve | C→S | Host approves request |
| join-reject | C→S | Host rejects request |
| leave-room | C→S | Leave room |
| participant-joined | S→C | New participant notification |
| participant-left | S→C | Participant left notification |
| participant-list | S→C | Current participant list |
| register-participant | C→S | Register for targeted messaging |
| torrent-magnet | C↔S | Share magnet URI |
| movie-loaded | C↔S | Movie ready notification |
| control-request | C→S | Playback control request |
| control-committed | S→C | Ordered control commit |
| control-ack | C→S | Control apply acknowledgment |
| playback-snapshot | S→C | Current playback state |
| sync-check | C→S | Request position reports |
| sync-report | C→S | Position report |
| sync-correct | S→C | Correct position command |
| sync-update | C↔S | State update |
| ready-to-start | C→S | Viewer ready |
| ready-count-update | S→C | Ready count update |
| start-playback | C→S | Start playback |
| playback-started | S→C | Playback started notification |
| start-webrtc | C↔S | Initiate WebRTC |
| ready-for-connection | C→S | Ready for WebRTC |
| offer | C↔S | WebRTC offer |
| answer | C↔S | WebRTC answer |
| ice-candidate | C↔S | ICE candidate |
| chat-message | C↔S | Chat message |
| error | S→C | Error notification |

**Legend**:
- C→S: Client to Server
- S→C: Server to Client
- C↔S: Bidirectional
