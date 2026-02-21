package handlers

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
	"net/url"
	"time"

	"github.com/biswa/sharestream-signal/internal/models"
	"github.com/biswa/sharestream-signal/internal/sync"
	"github.com/biswa/sharestream-signal/internal/turn"
	"github.com/gofrs/uuid"
	socketio "github.com/googollee/go-socket.io"
	"github.com/gorilla/mux"
)

type Handler struct {
	server       *socketio.Server
	rooms        *models.RoomManager
	syncManager  *sync.Manager
	turnGen      *turn.Generator
	participants map[string]*models.Participant
}

func New(server *socketio.Server, rooms *models.RoomManager, syncManager *sync.Manager, turnGen *turn.Generator) *Handler {
	return &Handler{
		server:       server,
		rooms:        rooms,
		syncManager:  syncManager,
		turnGen:      turnGen,
		participants: make(map[string]*models.Participant),
	}
}

func (h *Handler) HandleCreateRoom(conn socketio.Conn, data map[string]interface{}) {
	participantID, _ := data["participantId"].(string)
	name, _ := data["name"].(string)
	requestedCode, _ := data["requestedCode"].(string)

	code := requestedCode
	if code == "" {
		code = generateRoomCode()
	}

	room := &models.Room{
		Code:         code,
		Host:         participantID,
		Participants: make(map[string]*models.Participant),
		CreatedAt:    time.Now(),
	}

	participant := &models.Participant{
		ID:       participantID,
		Name:     name,
		SocketID: conn.ID(),
		Role:     "host",
		IsHost:   true,
		JoinedAt: time.Now(),
	}

	h.rooms.AddRoom(room)
	room.Mu.Lock()
	room.Participants[participantID] = participant
	room.Mu.Unlock()

	h.participants[conn.ID()] = participant

	room.Mu.RLock()
	roomCode := room.Code
	roomHost := room.Host
	room.Mu.RUnlock()

	conn.Emit("room-created", map[string]interface{}{
		"success": true,
		"room": map[string]interface{}{
			"code": roomCode,
			"host": roomHost,
			"role": "host",
		},
	})

	log.Printf("Room created: %s by %s", code, name)
}

func (h *Handler) HandleJoinRoom(conn socketio.Conn, data map[string]interface{}) {
	code, _ := data["code"].(string)
	participantID, _ := data["participantId"].(string)
	name, _ := data["name"].(string)

	room, exists := h.rooms.GetRoom(code)

	if !exists {
		conn.Emit("room-joined", map[string]interface{}{
			"success": false,
			"error":   "Room not found",
		})
		return
	}

	role := "viewer"
	isHost := false

	if len(room.Participants) == 0 {
		role = "host"
		isHost = true
	}

	participant := &models.Participant{
		ID:       participantID,
		Name:     name,
		SocketID: conn.ID(),
		Role:     role,
		IsHost:   isHost,
		JoinedAt: time.Now(),
	}

	room.Mu.Lock()
	room.Participants[participantID] = participant
	room.Mu.Unlock()

	h.participants[conn.ID()] = participant

	room.Mu.RLock()
	participantList := make([]map[string]interface{}, 0, len(room.Participants))
	for _, p := range room.Participants {
		participantList = append(participantList, map[string]interface{}{
			"id":   p.ID,
			"name": p.Name,
			"role": p.Role,
		})
	}
	room.Mu.RUnlock()

	conn.Emit("room-joined", map[string]interface{}{
		"success": true,
		"room": map[string]interface{}{
			"code": room.Code,
			"role": role,
		},
	})

	code = room.Code
	h.server.BroadcastToRoom("/", code, "participant-list", map[string]interface{}{
		"participants": participantList,
	})

	h.server.BroadcastToRoom("/", code, "participant-joined", map[string]interface{}{
		"id":   participantID,
		"name": name,
	})

	conn.Join(code)

	log.Printf("Participant %s joined room %s as %s", name, code, role)
}

func (h *Handler) HandleLeaveRoom(conn socketio.Conn) {
	participant, ok := h.participants[conn.ID()]
	if !ok {
		return
	}

	delete(h.participants, conn.ID())

	rooms := h.rooms.GetAllRooms()
	for _, room := range rooms {
		room.Mu.Lock()
		if _, exists := room.Participants[participant.ID]; exists {
			delete(room.Participants, participant.ID)

			room.Mu.Unlock()

			h.server.BroadcastToRoom("/", room.Code, "participant-left", map[string]interface{}{
				"id": participant.ID,
			})

			if len(room.Participants) == 0 {
				room.Mu.Lock()
				h.rooms.DeleteRoom(room.Code)
				room.Mu.Unlock()
			}

			break
		}
		room.Mu.Unlock()
	}
}

func (h *Handler) HandleDisconnect(connID string) {
	emptyConn := &socketioConn{id: connID}
	h.HandleLeaveRoom(emptyConn)
}

type socketioConn struct {
	id string
}

func (c *socketioConn) ID() string                                          { return c.id }
func (c *socketioConn) Context() interface{}                                { return nil }
func (c *socketioConn) SetContext(v interface{})                            {}
func (c *socketioConn) Namespace() string                                   { return "" }
func (c *socketioConn) Close() error                                        { return nil }
func (c *socketioConn) URL() url.URL                                        { return url.URL{} }
func (c *socketioConn) LocalAddr() net.Addr                                 { return nil }
func (c *socketioConn) RemoteAddr() net.Addr                                { return nil }
func (c *socketioConn) RemoteHeader() http.Header                           { return nil }
func (c *socketioConn) Emit(event string, args ...interface{})              {}
func (c *socketioConn) BroadcastTo(room, event string, args ...interface{}) {}
func (c *socketioConn) Join(room string)                                    {}
func (c *socketioConn) Leave(room string)                                   {}
func (c *socketioConn) LeaveAll()                                           {}
func (c *socketioConn) Rooms() []string                                     { return nil }

func (h *Handler) HandleTorrentMagnet(conn socketio.Conn, data map[string]interface{}) {
	magnetURI, _ := data["magnetURI"].(string)
	streamPath, _ := data["streamPath"].(string)
	name, _ := data["name"].(string)

	for _, room := range conn.Rooms() {
		if room != conn.ID() {
			h.server.BroadcastToRoom("/", room, "torrent-magnet", map[string]interface{}{
				"magnetURI":  magnetURI,
				"streamPath": streamPath,
				"name":       name,
			})
		}
	}

	log.Printf("Torrent magnet shared in room: %s", name)
}

func (h *Handler) HandleMovieLoaded(conn socketio.Conn, data map[string]interface{}) {
	name, _ := data["name"].(string)
	duration, _ := data["duration"].(float64)

	for _, room := range conn.Rooms() {
		if room != conn.ID() {
			h.server.BroadcastToRoom("/", room, "movie-loaded", map[string]interface{}{
				"name":     name,
				"duration": duration,
			})
		}
	}
}

func (h *Handler) HandleSyncPlay(conn socketio.Conn, data map[string]interface{}) {
	playTime, _ := data["time"].(float64)
	actionID, _ := data["actionId"].(string)

	for _, room := range conn.Rooms() {
		if room != conn.ID() {
			h.server.BroadcastToRoom("/", room, "sync-play", map[string]interface{}{
				"time":     playTime,
				"actionId": actionID,
			})
		}
	}
}

func (h *Handler) HandleSyncPause(conn socketio.Conn, data map[string]interface{}) {
	playTime, _ := data["time"].(float64)
	actionID, _ := data["actionId"].(string)

	for _, room := range conn.Rooms() {
		if room != conn.ID() {
			h.server.BroadcastToRoom("/", room, "sync-pause", map[string]interface{}{
				"time":     playTime,
				"actionId": actionID,
			})
		}
	}
}

func (h *Handler) HandleSyncSeek(conn socketio.Conn, data map[string]interface{}) {
	playTime, _ := data["time"].(float64)
	actionID, _ := data["actionId"].(string)

	for _, room := range conn.Rooms() {
		if room != conn.ID() {
			h.server.BroadcastToRoom("/", room, "sync-seek", map[string]interface{}{
				"time":     playTime,
				"actionId": actionID,
			})
		}
	}
}

func (h *Handler) HandleChatMessage(conn socketio.Conn, data map[string]interface{}) {
	participant, _ := h.participants[conn.ID()]

	text, _ := data["text"].(string)

	msg := map[string]interface{}{
		"id":         uuid.Must(uuid.NewV4()).String(),
		"senderId":   participant.ID,
		"sender":     participant.Name,
		"senderRole": participant.Role,
		"text":       text,
		"timestamp":  time.Now().UnixMilli(),
	}

	for _, room := range conn.Rooms() {
		if room != conn.ID() {
			h.server.BroadcastToRoom("/", room, "chat-message", msg)
		}
	}
}

func (h *Handler) HandleStartWebRTC(conn socketio.Conn, data map[string]interface{}) {
	peerID, _ := data["peerId"].(string)
	initiator, _ := data["initiator"].(bool)

	for _, room := range conn.Rooms() {
		if room != conn.ID() {
			h.server.BroadcastToRoom("/", room, "start-webrtc", map[string]interface{}{
				"peerId":    peerID,
				"initiator": initiator,
			})
		}
	}
}

func (h *Handler) HandleOffer(conn socketio.Conn, data map[string]interface{}) {
	toPeerID, _ := data["to"].(string)
	offer, _ := data["offer"].(map[string]interface{})

	if toPeerID == "" {
		log.Printf("Offer from %s missing 'to' field, ignoring", conn.ID())
		return
	}

	// Find the target participant's socket ID and send directly
	sent := false
	for _, roomCode := range conn.Rooms() {
		room, exists := h.rooms.GetRoom(roomCode)
		if !exists {
			continue
		}

		room.Mu.RLock()
		for _, p := range room.Participants {
			if p.ID == toPeerID {
				// Send directly to the target socket
				h.server.EmitTo(p.SocketID, "offer", map[string]interface{}{
					"from":  conn.ID(),
					"offer": offer,
				})
				sent = true
				log.Printf("Offer sent from %s to %s (socket: %s, room: %s)", conn.ID(), toPeerID, p.SocketID, roomCode)
				break
			}
		}
		room.Mu.RUnlock()
		if sent {
			break
		}
	}

	if !sent {
		log.Printf("Failed to send offer from %s to %s: target not found", conn.ID(), toPeerID)
	}
}

func (h *Handler) HandleAnswer(conn socketio.Conn, data map[string]interface{}) {
	toPeerID, _ := data["to"].(string)
	answer, _ := data["answer"].(map[string]interface{})

	if toPeerID == "" {
		log.Printf("Answer from %s missing 'to' field, ignoring", conn.ID())
		return
	}

	// Find the target participant's socket ID and send directly
	sent := false
	for _, roomCode := range conn.Rooms() {
		room, exists := h.rooms.GetRoom(roomCode)
		if !exists {
			continue
		}

		room.Mu.RLock()
		for _, p := range room.Participants {
			if p.ID == toPeerID {
				// Send directly to the target socket
				h.server.EmitTo(p.SocketID, "answer", map[string]interface{}{
					"from":   conn.ID(),
					"answer": answer,
				})
				sent = true
				log.Printf("Answer sent from %s to %s (socket: %s, room: %s)", conn.ID(), toPeerID, p.SocketID, roomCode)
				break
			}
		}
		room.Mu.RUnlock()
		if sent {
			break
		}
	}

	if !sent {
		log.Printf("Failed to send answer from %s to %s: target not found", conn.ID(), toPeerID)
	}
}

func (h *Handler) HandleICECandidate(conn socketio.Conn, data map[string]interface{}) {
	toPeerID, _ := data["to"].(string)
	candidate, _ := data["candidate"].(map[string]interface{})

	if toPeerID == "" {
		log.Printf("ICE candidate from %s missing 'to' field, ignoring", conn.ID())
		return
	}

	// Find the target participant's socket ID and send directly
	sent := false
	for _, roomCode := range conn.Rooms() {
		room, exists := h.rooms.GetRoom(roomCode)
		if !exists {
			continue
		}

		room.Mu.RLock()
		for _, p := range room.Participants {
			if p.ID == toPeerID {
				// Send directly to the target socket
				h.server.EmitTo(p.SocketID, "ice-candidate", map[string]interface{}{
					"from":      conn.ID(),
					"candidate": candidate,
				})
				sent = true
				// Don't log every ICE candidate to avoid spam
				break
			}
		}
		room.Mu.RUnlock()
		if sent {
			break
		}
	}

	if !sent {
		log.Printf("Failed to send ICE candidate from %s to %s: target not found", conn.ID(), toPeerID)
	}
}

func (h *Handler) HandleSyncCheck(conn socketio.Conn, data map[string]interface{}) {
	roomCode, _ := data["roomCode"].(string)
	timestamp := time.Now().UnixMilli()

	h.server.BroadcastToRoom("/", roomCode, "sync-check", map[string]interface{}{
		"roomCode":  roomCode,
		"timestamp": timestamp,
	})
}

func (h *Handler) HandleSyncReport(conn socketio.Conn, data map[string]interface{}) {
	roomCode, _ := data["roomCode"].(string)
	playbackTime, _ := data["playbackTime"].(float64)
	playing, _ := data["playing"].(bool)
	timestamp := time.Now().UnixMilli()

	report := &sync.PlaybackReport{
		RoomCode:      roomCode,
		ParticipantID: conn.ID(),
		PlaybackTime:  playbackTime,
		Playing:       playing,
		Timestamp:     timestamp,
	}

	h.syncManager.AddReport(roomCode, report)

	h.server.BroadcastToRoom("/", roomCode, "sync-report", map[string]interface{}{
		"roomCode":      roomCode,
		"participantId": conn.ID(),
		"playbackTime":  playbackTime,
		"playing":       playing,
		"timestamp":     timestamp,
	})
}

func (h *Handler) HandleSyncCorrect(conn socketio.Conn, data map[string]interface{}) {
	roomCode, _ := data["roomCode"].(string)
	playbackTime, _ := data["playbackTime"].(float64)
	playing, _ := data["playing"].(bool)
	actionID, _ := data["actionId"].(string)

	h.server.BroadcastToRoom("/", roomCode, "sync-correct", map[string]interface{}{
		"roomCode":     roomCode,
		"playbackTime": playbackTime,
		"playing":      playing,
		"actionId":     actionID,
	})
}

func (h *Handler) HandleReadyForConnection(conn socketio.Conn, data map[string]interface{}) {
	log.Printf("Client ready for WebRTC connection: %s", conn.ID())
}

func (h *Handler) GetRoom(w http.ResponseWriter, r *http.Request) {
	code := mux.Vars(r)["code"]

	room, exists := h.rooms.GetRoom(code)

	if !exists {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte(`{"error":"Room not found"}`))
		return
	}

	room.Mu.RLock()
	defer room.Mu.RUnlock()

	participants := make([]map[string]interface{}, 0, len(room.Participants))
	for _, p := range room.Participants {
		participants = append(participants, map[string]interface{}{
			"id":   p.ID,
			"name": p.Name,
			"role": p.Role,
		})
	}

	resp := map[string]interface{}{
		"code":         room.Code,
		"host":         room.Host,
		"participants": participants,
	}

	jsonBytes, _ := json.Marshal(resp)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(jsonBytes)
}

func (h *Handler) GetTURNCredentials(w http.ResponseWriter, r *http.Request) {
	username, password, ok := r.BasicAuth()
	if !ok {
		username = uuid.Must(uuid.NewV4()).String()
		password = uuid.Must(uuid.NewV4()).String()
	}

	credentials := h.turnGen.GenerateCredentials(username, password)

	jsonBytes, _ := json.Marshal(credentials)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(jsonBytes)
}

func generateRoomCode() string {
	return uuid.Must(uuid.NewV4()).String()[:8]
}
