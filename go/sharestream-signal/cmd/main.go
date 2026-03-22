package main

import (
	"bufio"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	pionLogging "github.com/pion/logging"
	"github.com/pion/turn/v4"
	"github.com/zishang520/engine.io/v2/types"
	"github.com/zishang520/socket.io/v2/socket"
)

const inviteTokenTTL = 24 * time.Hour

var (
	port     = flag.Int("port", 3001, "Server port")
	turnPort = flag.Int("turn-port", 3478, "Embedded TURN server port")
	noTunnel = flag.Bool("no-tunnel", false, "Disable automatic tunnel creation")
	noTurn   = flag.Bool("no-turn", false, "Disable embedded TURN server")

	io_       *socket.Server
	tunnelURL string
	tunnelMu  sync.RWMutex

	// Embedded TURN server state
	turnTunnelURL string
	turnTunnelMu  sync.RWMutex
	turnUsername  string
	turnPassword  string
	turnServer    *turn.Server

	// Socket to participant ID mapping for WebRTC signaling
	socketToParticipant = make(map[string]string)
	participantToSocket = make(map[string]string)
	participantMu       sync.RWMutex

	cloudflaredCmd   *exec.Cmd
	cloudflaredCmdMu sync.Mutex
	shuttingDown     bool
)

// ── Room Management ──────────────────────────────────────────────────────────

type Room struct {
	Code            string
	Host            string
	Approved        map[string]bool
	Pending         map[string]string
	ApprovedNames   map[string]string
	ReadyViewers    map[string]bool
	LastControlSeq  int64
	LastActionIDs   map[string]int64
	LastControlAt   map[string]int64
	LastSeekAt      map[string]int64
	PlaybackTime    float64
	PlaybackPlaying bool
	HostTimestamp   time.Time
	HostState       string
	mu              sync.RWMutex
}

type RoomManager struct {
	rooms map[string]*Room
	mu    sync.RWMutex
}

func NewRoomManager() *RoomManager {
	return &RoomManager{rooms: make(map[string]*Room)}
}

func (rm *RoomManager) CreateRoom(code, hostID string) *Room {
	rm.mu.Lock()
	defer rm.mu.Unlock()
	room := &Room{
		Code:          code,
		Host:          hostID,
		Approved:      make(map[string]bool),
		Pending:       make(map[string]string),
		ApprovedNames: make(map[string]string),
		ReadyViewers:  make(map[string]bool),
		LastActionIDs: make(map[string]int64),
		LastControlAt: make(map[string]int64),
		LastSeekAt:    make(map[string]int64),
	}
	rm.rooms[code] = room
	return room
}

func (rm *RoomManager) GetRoom(code string) *Room {
	rm.mu.RLock()
	defer rm.mu.RUnlock()
	return rm.rooms[code]
}

func (rm *RoomManager) DeleteRoom(code string) {
	rm.mu.Lock()
	defer rm.mu.Unlock()
	delete(rm.rooms, code)
}

var roomManager = NewRoomManager()

// ── Main ─────────────────────────────────────────────────────────────────────

func main() {
	flag.Parse()

	// Generate random TURN credentials
	turnUsername = fmt.Sprintf("sharestream_%d", rand.Intn(999999))
	turnPassword = generateRandomString(24)
	log.Printf("[turn] Generated TURN credentials: user=%s", turnUsername)

	// Start embedded TURN server (if not disabled)
	if !*noTurn {
		go func() {
			if err := startEmbeddedTURN(*turnPort); err != nil {
				log.Printf("[turn] Failed to start embedded TURN: %v", err)
			} else {
				log.Printf("[turn] Embedded TURN server running on port %d", *turnPort)
			}
		}()
	}

	// Start cloudflared tunnel in background (if not disabled)
	if !*noTunnel {
		go startCloudflaredTunnel(*port)
	}

	// Create Socket.IO v4 server with CORS
	opts := socket.DefaultServerOptions()
	opts.SetCors(&types.Cors{
		Origin:      "*",
		Credentials: true,
	})
	opts.SetAllowEIO3(true) // Accept both EIO=3 and EIO=4 clients

	io_ = socket.NewServer(nil, opts)

	// Register connection handler
	io_.On("connection", func(clients ...any) {
		client := clients[0].(*socket.Socket)
		log.Printf("Client connected: %s", client.Id())

		registerEventHandlers(client)

		client.On("disconnect", func(args ...any) {
			reason := ""
			if len(args) > 0 {
				reason = fmt.Sprintf("%v", args[0])
			}
			log.Printf("Client disconnected: %s (reason: %s)", client.Id(), reason)

			// Clean up participant mapping
			participantMu.Lock()
			participantID := socketToParticipant[string(client.Id())]
			delete(socketToParticipant, string(client.Id()))
			delete(participantToSocket, participantID)
			participantMu.Unlock()

			if participantID != "" {
				cleanupParticipantFromRooms(participantID)
			}

			if participantID != "" {
				log.Printf("[JOIN] Cleaned up mapping for participant %s", participantID)
			}
		})
	})

	// ── HTTP Router ──────────────────────────────────────────────────────
	router := mux.NewRouter()

	// Mount Socket.IO handler
	router.PathPrefix("/socket.io/").Handler(io_.ServeHandler(opts))

	// REST API endpoints
	router.HandleFunc("/health", handleHealth).Methods("GET")
	router.HandleFunc("/api/tunnel", handleTunnelURL).Methods("GET")
	router.HandleFunc("/api/turn", handleTurnServers).Methods("GET")
	router.HandleFunc("/api/room/{code}", handleGetRoom).Methods("GET")
	router.HandleFunc("/join/{code}", handleJoinPage).Methods("GET")
	router.HandleFunc("/api/room/{code}/ready", handleGetReadyCount).Methods("GET")

	// Start HTTP server
	addr := fmt.Sprintf(":%d", *port)
	log.Printf("ShareStream Signal Server starting on %s", addr)

	srv := &http.Server{Addr: addr, Handler: router}
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Wait for tunnel (if enabled)
	if !*noTunnel {
		select {
		case <-time.After(30 * time.Second):
			log.Println("Tunnel not ready after 30s, continuing without tunnel")
		case <-tunnelReadyCh:
			log.Println("Tunnel is ready")
		}
	}

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down...")
	if turnServer != nil {
		turnServer.Close()
	}
	stopCloudflaredTunnel()
	io_.Close(nil)
	srv.Close()
}

// ── Socket.IO Event Handlers ─────────────────────────────────────────────────

func registerEventHandlers(client *socket.Socket) {
	client.On("create-room", func(args ...any) {
		data := parseData(args)
		handleCreateRoom(client, data)
	})
	client.On("join-room", func(args ...any) {
		data := parseData(args)
		handleJoinRoom(client, data)
	})
	client.On("leave-room", func(args ...any) {
		data := parseData(args)
		handleLeaveRoom(client, data)
	})
	client.On("join-request", func(args ...any) {
		data := parseData(args)
		handleJoinRequest(client, data)
	})
	client.On("join-approve", func(args ...any) {
		data := parseData(args)
		handleJoinApprove(client, data)
	})
	client.On("register-participant", func(args ...any) {
		data := parseData(args)
		participantID, ok := data["participantId"].(string)
		if ok && participantID != "" {
			client.Join(socket.Room(participantID))

			// Store the mapping
			participantMu.Lock()
			socketToParticipant[string(client.Id())] = participantID
			participantToSocket[participantID] = string(client.Id())
			participantMu.Unlock()

			log.Printf("[JOIN] Client %s registered as participant %s", client.Id(), participantID)
		}
	})
	client.On("join-reject", func(args ...any) {
		data := parseData(args)
		handleJoinReject(client, data)
	})
	client.On("request-join-approval", func(args ...any) {
		data := parseData(args)
		handleRequestJoinApproval(client, data)
	})
	client.On("torrent-magnet", func(args ...any) {
		data := parseData(args)
		handleBroadcastToRooms(client, "torrent-magnet", data)
	})
	client.On("movie-loaded", func(args ...any) {
		data := parseData(args)
		handleBroadcastToRooms(client, "movie-loaded", data)
	})
	client.On("control-request", func(args ...any) {
		data := parseData(args)
		handleControlRequest(client, data)
	})
	client.On("control-ack", func(args ...any) {
		data := parseData(args)
		handleControlAck(client, data)
	})
	client.On("start-webrtc", func(args ...any) {
		data := parseData(args)
		handleBroadcastToRooms(client, "start-webrtc", data)
	})
	client.On("offer", func(args ...any) {
		data := parseData(args)
		handleTargetedEmit(client, "offer", data)
	})
	client.On("answer", func(args ...any) {
		data := parseData(args)
		handleTargetedEmit(client, "answer", data)
	})
	client.On("ice-candidate", func(args ...any) {
		data := parseData(args)
		handleTargetedEmit(client, "ice-candidate", data)
	})
	client.On("ready-for-connection", func(args ...any) {
		// Get our participant ID
		participantMu.RLock()
		myParticipantID := socketToParticipant[string(client.Id())]
		participantMu.RUnlock()

		if myParticipantID == "" {
			log.Printf("[webrtc] Warning: client %s not registered, using socket ID", client.Id())
			myParticipantID = string(client.Id())
		}

		// When a client is ready, notify all other participants to start WebRTC
		for _, room := range client.Rooms().Keys() {
			// Skip the client's own socket room and participant room
			if room == socket.Room(client.Id()) || room == socket.Room(myParticipantID) {
				continue
			}

			// Get the room to find participants
			r := roomManager.GetRoom(string(room))
			if r == nil {
				continue
			}

			// Notify each participant in the room
			r.mu.RLock()
			for participantID := range r.Approved {
				if participantID == myParticipantID {
					continue // Don't notify ourselves
				}

				// Determine who is the initiator based on ID comparison
				// The peer with lexicographically smaller ID initiates
				isInitiator := myParticipantID < participantID

				// Send to the participant's room
				io_.To(socket.Room(participantID)).Emit("start-webrtc", map[string]interface{}{
					"peerId":    myParticipantID,
					"initiator": isInitiator,
				})
				log.Printf("[webrtc] Notified %s about %s (initiator: %v)", participantID, myParticipantID, isInitiator)
			}
			r.mu.RUnlock()
		}
	})
	client.On("chat-message", func(args ...any) {
		data := parseData(args)
		handleBroadcastToRooms(client, "chat-message", data)
	})
	client.On("ready-to-start", func(args ...any) {
		data := parseData(args)
		handleReadyToStart(client, data)
	})
	client.On("start-playback", func(args ...any) {
		data := parseData(args)
		handleStartPlayback(client, data)
	})
	client.On("sync-check", func(args ...any) {
		data := parseData(args)
		handleSyncCheck(client, data)
	})
	client.On("sync-report", func(args ...any) {
		data := parseData(args)
		handleSyncReport(client, data)
	})
	client.On("sync-correct", func(args ...any) {
		data := parseData(args)
		handleSyncCorrect(client, data)
	})
	client.On("sync-update", func(args ...any) {
		data := parseData(args)
		handleSyncUpdate(client, data)
	})

	// Torrent peer exchange
	client.On("torrent-peer-info", func(args ...any) {
		data := parseData(args)
		handleTorrentPeerExchange(client, data)
	})
}

// parseData extracts the first argument as a map[string]interface{}.
// The zishang520/socket.io library delivers JSON data as raw values;
// we normalise it to map form for all handlers.
func parseData(args []any) map[string]interface{} {
	if len(args) == 0 {
		return map[string]interface{}{}
	}

	switch v := args[0].(type) {
	case map[string]interface{}:
		return v
	case string:
		// Try to parse as JSON string
		var m map[string]interface{}
		if err := json.Unmarshal([]byte(v), &m); err == nil {
			return m
		}
		return map[string]interface{}{"data": v}
	default:
		// Try JSON round-trip for other types
		b, err := json.Marshal(v)
		if err != nil {
			return map[string]interface{}{}
		}
		var m map[string]interface{}
		if err := json.Unmarshal(b, &m); err != nil {
			return map[string]interface{}{}
		}
		return m
	}
}

// ── Room Event Handlers ──────────────────────────────────────────────────────

func handleCreateRoom(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Create room: %+v", data)
	participantID, _ := data["participantId"].(string)
	name, _ := data["name"].(string)
	if participantID == "" {
		participantID = string(s.Id())
	}
	if name == "" {
		name = "Host"
	}

	participantMu.Lock()
	socketToParticipant[string(s.Id())] = participantID
	participantToSocket[participantID] = string(s.Id())
	participantMu.Unlock()

	code := generateRoomCode()
	room := roomManager.CreateRoom(code, participantID)
	room.mu.Lock()
	room.Approved[participantID] = true
	room.ApprovedNames[participantID] = name
	room.mu.Unlock()

	s.Join(socket.Room(code))
	s.Join(socket.Room(participantID))

	tunnelMu.RLock()
	tURL := tunnelURL
	tunnelMu.RUnlock()

	s.Emit("room-created", map[string]interface{}{
		"success": true,
		"room": map[string]interface{}{
			"code":        code,
			"role":        "host",
			"tunnel":      tURL,
			"inviteToken": makeInviteToken(code),
		},
	})
}

func handleJoinRoom(s *socket.Socket, data map[string]interface{}) {
	log.Printf("[JOIN] Join room from %s: %+v", s.Id(), data)
	code, ok := data["code"].(string)
	participantID, pOk := data["participantId"].(string)
	if !ok {
		s.Emit("room-joined", map[string]interface{}{
			"success": false,
			"error":   "invalid room code",
		})
		return
	}
	if !pOk {
		participantID = string(s.Id())
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		s.Emit("room-joined", map[string]interface{}{
			"success": false,
			"error":   "room not found",
		})
		return
	}

	room.mu.RLock()
	approved := room.Approved[participantID]
	name := room.ApprovedNames[participantID]
	room.mu.RUnlock()

	if !approved {
		s.Emit("room-joined", map[string]interface{}{
			"success":          false,
			"error":            "use join-request event to join",
			"requiresApproval": true,
		})
		return
	}

	s.Join(socket.Room(code))
	log.Printf("[JOIN] Socket %s joined room %s as participant %s (%s)", s.Id(), code, participantID, name)
	s.Emit("room-joined", map[string]interface{}{
		"success": true,
		"room": map[string]interface{}{
			"code": code,
			"role": "viewer",
		},
	})

	room.mu.RLock()
	lastSeq := room.LastControlSeq
	lastTime := room.PlaybackTime
	playing := room.PlaybackPlaying
	room.mu.RUnlock()
	if lastSeq > 0 {
		actionType := "pause"
		if playing {
			actionType = "play"
		}
		s.Emit("playback-snapshot", map[string]interface{}{
			"serverSeq": lastSeq,
			"playback": map[string]interface{}{
				"serverSeq": lastSeq,
				"time":      lastTime,
				"type":      actionType,
			},
		})
	}

	io_.To(socket.Room(code)).Emit("participant-joined", map[string]interface{}{
		"id":   participantID,
		"name": name,
	})
}

func handleLeaveRoom(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Leave room: %+v", data)
	code, ok := data["code"].(string)
	if !ok {
		// If no code provided, try to leave all rooms
		rooms := s.Rooms().Keys()
		for _, room := range rooms {
			if room != socket.Room(s.Id()) {
				s.Leave(room)
			}
		}
		return
	}

	// Get participant ID for the leaving socket
	participantMu.RLock()
	participantID := socketToParticipant[string(s.Id())]
	participantMu.RUnlock()

	s.Leave(socket.Room(code))

	// Clean up room state
	room := roomManager.GetRoom(code)
	if room != nil {
		room.mu.Lock()
		delete(room.Approved, participantID)
		delete(room.ApprovedNames, participantID)
		delete(room.Pending, participantID)
		delete(room.ReadyViewers, string(s.Id()))
		room.mu.Unlock()
	}

	emitID := participantID
	if emitID == "" {
		emitID = string(s.Id())
	}
	io_.To(socket.Room(code)).Emit("participant-left", map[string]interface{}{
		"id": emitID,
	})
}

func cleanupParticipantFromRooms(participantID string) {
	roomManager.mu.RLock()
	rooms := make([]*Room, 0, len(roomManager.rooms))
	for _, room := range roomManager.rooms {
		rooms = append(rooms, room)
	}
	roomManager.mu.RUnlock()

	for _, room := range rooms {
		room.mu.Lock()
		_, wasApproved := room.Approved[participantID]
		delete(room.Approved, participantID)
		delete(room.ApprovedNames, participantID)
		delete(room.Pending, participantID)
		for sid := range room.ReadyViewers {
			if sid == participantID {
				delete(room.ReadyViewers, sid)
			}
		}
		room.mu.Unlock()

		if wasApproved {
			io_.To(socket.Room(room.Code)).Emit("participant-left", map[string]interface{}{
				"id": participantID,
			})
		}
	}
}

func handleJoinRequest(s *socket.Socket, data map[string]interface{}) {
	log.Printf("[JOIN] Join request from %s: %+v", s.Id(), data)
	code, ok := data["code"].(string)
	name, nameOk := data["name"].(string)
	participantID, pOk := data["participantId"].(string)
	inviteToken, _ := data["inviteToken"].(string)
	if !ok || !nameOk || !pOk {
		s.Emit("join-request-result", map[string]interface{}{
			"success": false,
			"error":   "invalid request",
		})
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		s.Emit("join-request-result", map[string]interface{}{
			"success": false,
			"error":   "room not found",
		})
		return
	}

	if inviteToken == "" {
		log.Printf("[JOIN] Missing invite token for room %s participant %s", code, participantID)
		s.Emit("join-request-result", map[string]interface{}{
			"success": false,
			"error":   "invite token required",
		})
		return
	}

	if !validateInviteToken(code, inviteToken) {
		log.Printf("[JOIN] Invalid invite token for room %s participant %s", code, participantID)
		s.Emit("join-request-result", map[string]interface{}{
			"success": false,
			"error":   "invalid or expired invite token",
		})
		return
	}

	log.Printf("[JOIN] Storing join request - participantID: %s, name: %s, socket: %s", participantID, name, s.Id())

	room.mu.Lock()
	room.Pending[participantID] = name
	room.mu.Unlock()

	s.Emit("join-request-result", map[string]interface{}{
		"success":       true,
		"status":        "pending",
		"participantId": participantID,
	})

	// Notify the host
	log.Printf("[JOIN] Notifying host %s of join request from participant %s (%s)", room.Host, participantID, name)
	io_.To(socket.Room(room.Host)).Emit("join-request", map[string]interface{}{
		"participantId": participantID,
		"name":          name,
		"code":          code,
	})
}

func handleJoinApprove(s *socket.Socket, data map[string]interface{}) {
	log.Printf("[JOIN] Join approve from host %s: %+v", s.Id(), data)
	code, ok := data["code"].(string)
	participantID, pOk := data["participantId"].(string)
	if !ok || !pOk {
		s.Emit("join-approve-result", map[string]interface{}{
			"success": false,
			"error":   "invalid request",
		})
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		s.Emit("join-approve-result", map[string]interface{}{
			"success": false,
			"error":   "room not found",
		})
		return
	}

	room.mu.Lock()
	if name, exists := room.Pending[participantID]; exists {
		room.Approved[participantID] = true
		room.ApprovedNames[participantID] = name
		delete(room.Pending, participantID)
		log.Printf("[JOIN] Approved participant %s (%s) for room %s", participantID, name, code)
	} else {
		log.Printf("[JOIN] Warning: participant %s not in pending list for room %s", participantID, code)
	}
	room.mu.Unlock()

	s.Emit("join-approve-result", map[string]interface{}{
		"success":       true,
		"participantId": participantID,
	})

	// Notify the approved participant using socket room
	io_.To(socket.Room(participantID)).Emit("join-approved", map[string]interface{}{
		"code": code,
	})

	room.mu.RLock()
	name := room.ApprovedNames[participantID]
	room.mu.RUnlock()
	_ = name
}

func handleJoinReject(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Join reject: %+v", data)
	code, ok := data["code"].(string)
	participantID, pOk := data["participantId"].(string)
	if !ok || !pOk {
		s.Emit("join-reject-result", map[string]interface{}{
			"success": false,
			"error":   "invalid request",
		})
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		s.Emit("join-reject-result", map[string]interface{}{
			"success": false,
			"error":   "room not found",
		})
		return
	}

	room.mu.Lock()
	delete(room.Pending, participantID)
	room.mu.Unlock()

	s.Emit("join-reject-result", map[string]interface{}{
		"success":       true,
		"participantId": participantID,
	})

	io_.To(socket.Room(participantID)).Emit("join-rejected", map[string]interface{}{
		"code": code,
	})
}

func handleRequestJoinApproval(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Request join approval: %+v", data)
	code, ok := data["code"].(string)
	if !ok {
		s.Emit("join-approval-status", map[string]interface{}{
			"success": false,
			"error":   "invalid request",
		})
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		s.Emit("join-approval-status", map[string]interface{}{
			"success": false,
			"error":   "room not found",
		})
		return
	}

	// Look up participant ID from socket ID
	participantMu.RLock()
	participantID := socketToParticipant[string(s.Id())]
	participantMu.RUnlock()

	room.mu.RLock()
	_, isApproved := room.Approved[participantID]
	_, isPending := room.Pending[participantID]
	room.mu.RUnlock()

	if isApproved {
		s.Emit("join-approval-status", map[string]interface{}{
			"success": true,
			"status":  "approved",
		})
	} else if isPending {
		s.Emit("join-approval-status", map[string]interface{}{
			"success": true,
			"status":  "pending",
		})
	} else {
		s.Emit("join-approval-status", map[string]interface{}{
			"success": true,
			"status":  "none",
		})
	}
}

// ── Broadcast / Targeted Helpers ─────────────────────────────────────────────

// handleBroadcastToRooms broadcasts an event to all rooms the socket is in
// (excluding the socket's own ID room).
func handleBroadcastToRooms(s *socket.Socket, event string, data map[string]interface{}) {
	log.Printf("[broadcast] %s from %s: %+v", event, s.Id(), data)
	rooms := s.Rooms().Keys()
	if len(rooms) == 0 {
		log.Printf("[broadcast] Warning: socket %s is not in any rooms", s.Id())
		return
	}

	// Get participant ID to skip participant-specific rooms
	participantMu.RLock()
	myParticipantID := socketToParticipant[string(s.Id())]
	participantMu.RUnlock()

	for _, room := range rooms {
		// Skip the socket's personal ID room
		if room == socket.Room(s.Id()) {
			continue
		}
		// Skip participant ID rooms (only broadcast to actual room-code rooms)
		if myParticipantID != "" && room == socket.Room(myParticipantID) {
			continue
		}
		log.Printf("[broadcast] Emitting %s to room %s", event, room)
		io_.To(room).Emit(event, data)
	}
}

// handleTargetedEmit sends an event to a specific target socket by ID.
func handleTargetedEmit(s *socket.Socket, event string, data map[string]interface{}) {
	log.Printf("[targeted] %s from %s: %+v", event, s.Id(), data)
	targetID, ok := data["to"].(string)
	if !ok {
		// Also try "targetId" for backwards compat
		targetID, ok = data["targetId"].(string)
		if !ok {
			log.Printf("[targeted] Warning: no 'to' or 'targetId' field in %s event", event)
			return
		}
	}

	// Get sender's participant ID for WebRTC signaling
	participantMu.RLock()
	senderParticipantID := socketToParticipant[string(s.Id())]
	participantMu.RUnlock()

	// Use participant ID if available, otherwise fall back to socket ID
	if senderParticipantID != "" {
		data["from"] = senderParticipantID
	} else {
		data["from"] = string(s.Id())
	}

	log.Printf("[targeted] Forwarding %s to %s (from: %s)", event, targetID, data["from"])
	io_.To(socket.Room(targetID)).Emit(event, data)
}

// ── Playback / Sync Handlers ─────────────────────────────────────────────────

func handleReadyToStart(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Ready to start: %+v", data)
	code, ok := data["code"].(string)
	if !ok {
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		return
	}

	room.mu.Lock()
	room.ReadyViewers[string(s.Id())] = true
	count := len(room.ReadyViewers)
	room.mu.Unlock()

	s.Emit("ready-confirmed", map[string]interface{}{
		"success": true,
	})

	io_.To(socket.Room(room.Host)).Emit("ready-count-update", map[string]interface{}{
		"readyCount": count,
	})
}

func handleStartPlayback(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Start playback: %+v", data)
	code, ok := data["code"].(string)
	if !ok {
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		return
	}

	room.mu.Lock()
	room.ReadyViewers = make(map[string]bool)
	room.mu.Unlock()

	io_.To(socket.Room(code)).Emit("playback-started", map[string]interface{}{
		"hostId": string(s.Id()),
	})
}

func handleSyncCheck(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Sync check: %+v", data)
	code, ok := data["code"].(string)
	if !ok {
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		return
	}

	io_.To(socket.Room(code)).Emit("sync-check", map[string]interface{}{
		"timestamp": time.Now().UnixMilli(),
	})
}

func handleSyncReport(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Sync report: %+v", data)
	code, ok := data["code"].(string)
	if !ok {
		return
	}

	participantMu.RLock()
	participantID := socketToParticipant[string(s.Id())]
	participantMu.RUnlock()
	if participantID == "" {
		participantID = string(s.Id())
	}
	timeVal, _ := data["time"].(float64)
	playing, _ := data["playing"].(bool)
	buffered, _ := data["buffered"].(float64)

	room := roomManager.GetRoom(code)
	if room == nil {
		return
	}

	io_.To(socket.Room(room.Host)).Emit("sync-report", map[string]interface{}{
		"participantId": participantID,
		"playbackTime":  timeVal,
		"playing":       playing,
		"buffered":      buffered,
	})
}

func handleSyncCorrect(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Sync correct: %+v", data)
	participantID, ok := data["participantId"].(string)
	if !ok {
		return
	}

	timeVal, tOk := data["time"].(float64)
	playing, playOk := data["playing"].(bool)
	code, _ := data["code"].(string)
	if !tOk || !playOk {
		return
	}

	if code != "" {
		room := roomManager.GetRoom(code)
		if room == nil {
			return
		}
		participantMu.RLock()
		senderParticipantID := socketToParticipant[string(s.Id())]
		participantMu.RUnlock()
		room.mu.RLock()
		senderIsHost := senderParticipantID != "" && senderParticipantID == room.Host
		room.mu.RUnlock()
		if !senderIsHost {
			return
		}
	}

	io_.To(socket.Room(participantID)).Emit("sync-correct", map[string]interface{}{
		"playbackTime": timeVal,
		"playing":      playing,
		"actionId":     time.Now().UnixMilli(),
	})
}

func handleSyncUpdate(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Sync update: %+v", data)
	code, ok := data["code"].(string)
	if !ok {
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		return
	}

	timeVal, tOk := data["time"].(float64)
	playing, _ := data["playing"].(bool)

	if tOk {
		room.mu.Lock()
		room.HostTimestamp = time.Now()
		if playing {
			room.HostState = "playing"
		} else {
			room.HostState = "paused"
		}
		room.mu.Unlock()
	}

	io_.To(socket.Room(code)).Emit("sync-update", map[string]interface{}{
		"timestamp": time.Now().UnixMilli(),
		"time":      timeVal,
		"playing":   playing,
	})
}

func handleControlRequest(s *socket.Socket, data map[string]interface{}) {
	code, ok := data["code"].(string)
	if !ok || code == "" {
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		return
	}

	participantMu.RLock()
	senderParticipantID := socketToParticipant[string(s.Id())]
	participantMu.RUnlock()
	if senderParticipantID == "" {
		senderParticipantID = string(s.Id())
	}

	actionID, _ := data["actionId"].(string)
	actionType, _ := data["actionType"].(string)
	targetTimeSec, _ := data["targetTimeSec"].(float64)
	playWhenReady, _ := data["playWhenReady"].(bool)
	if actionType == "" {
		return
	}

	nowMs := time.Now().UnixMilli()

	room.mu.Lock()
	if _, joined := room.Approved[senderParticipantID]; !joined {
		room.mu.Unlock()
		return
	}

	const controlRateWindowMs int64 = 1000
	const controlRateLimitPerSec int64 = 6
	const seekCooldownMs int64 = 300

	lastControlAt := room.LastControlAt[senderParticipantID]
	if lastControlAt > 0 && (nowMs-lastControlAt) < (controlRateWindowMs/controlRateLimitPerSec) {
		room.mu.Unlock()
		return
	}
	room.LastControlAt[senderParticipantID] = nowMs

	if actionType == "seek" {
		lastSeekAt := room.LastSeekAt[senderParticipantID]
		if lastSeekAt > 0 && (nowMs-lastSeekAt) < seekCooldownMs {
			room.mu.Unlock()
			return
		}
		room.LastSeekAt[senderParticipantID] = nowMs
	}

	if actionID != "" {
		if seenAt, exists := room.LastActionIDs[actionID]; exists && (nowMs-seenAt) < 120000 {
			room.mu.Unlock()
			return
		}
		room.LastActionIDs[actionID] = nowMs
	}

	for id, seenAt := range room.LastActionIDs {
		if (nowMs - seenAt) > 120000 {
			delete(room.LastActionIDs, id)
		}
	}

	room.LastControlSeq++
	serverSeq := room.LastControlSeq
	room.PlaybackTime = targetTimeSec
	if actionType == "play" {
		room.PlaybackPlaying = true
	} else if actionType == "pause" {
		room.PlaybackPlaying = false
	} else {
		room.PlaybackPlaying = playWhenReady
	}
	playing := room.PlaybackPlaying
	room.mu.Unlock()

	io_.To(socket.Room(code)).Emit("control-committed", map[string]interface{}{
		"serverSeq":              serverSeq,
		"actionId":               actionID,
		"actionType":             actionType,
		"targetTimeSec":          targetTimeSec,
		"playWhenReady":          playing,
		"initiatorParticipantId": senderParticipantID,
		"serverCommitMs":         nowMs,
	})
}

func handleControlAck(s *socket.Socket, data map[string]interface{}) {
	code, ok := data["code"].(string)
	if !ok || code == "" {
		return
	}

	room := roomManager.GetRoom(code)
	if room == nil {
		return
	}

	participantMu.RLock()
	senderParticipantID := socketToParticipant[string(s.Id())]
	participantMu.RUnlock()
	if senderParticipantID == "" {
		senderParticipantID = string(s.Id())
	}

	room.mu.RLock()
	_, joined := room.Approved[senderParticipantID]
	hostID := room.Host
	room.mu.RUnlock()
	if !joined {
		return
	}

	serverSeq, _ := data["serverSeq"].(float64)
	currentTimeSec, _ := data["currentTimeSec"].(float64)
	playing, _ := data["playing"].(bool)
	bufferedSec, _ := data["bufferedSec"].(float64)

	io_.To(socket.Room(hostID)).Emit("control-ack", map[string]interface{}{
		"participantId":  senderParticipantID,
		"serverSeq":      int64(serverSeq),
		"currentTimeSec": currentTimeSec,
		"playing":        playing,
		"bufferedSec":    bufferedSec,
		"timestamp":      time.Now().UnixMilli(),
	})
}

// ── HTTP Handlers ────────────────────────────────────────────────────────────

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"status":"ok"}`)
}

func handleTunnelURL(w http.ResponseWriter, r *http.Request) {
	tunnelMu.RLock()
	tURL := tunnelURL
	tunnelMu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	if tURL != "" {
		fmt.Fprintf(w, `{"tunnel":"%s","ready":true}`, tURL)
	} else {
		fmt.Fprintf(w, `{"tunnel":"","ready":false}`)
	}
}

func handleTurnServers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	iceServers := []map[string]interface{}{
		{"urls": "stun:stun.l.google.com:19302"},
		{"urls": "stun:stun1.l.google.com:19302"},
	}

	// Add embedded TURN server if running
	if !*noTurn && turnUsername != "" && turnPassword != "" {
		// For local clients, use localhost TURN
		iceServers = append(iceServers, map[string]interface{}{
			"urls":       fmt.Sprintf("turn:127.0.0.1:%d?transport=tcp", *turnPort),
			"username":   turnUsername,
			"credential": turnPassword,
		})
		iceServers = append(iceServers, map[string]interface{}{
			"urls":       fmt.Sprintf("turn:127.0.0.1:%d", *turnPort),
			"username":   turnUsername,
			"credential": turnPassword,
		})

		// For remote clients, detect their IP and serve appropriate TURN URL
		remoteIP := r.Header.Get("X-Forwarded-For")
		if remoteIP == "" {
			remoteIP = r.RemoteAddr
		}
		isLocal := strings.HasPrefix(remoteIP, "127.") ||
			strings.HasPrefix(remoteIP, "localhost") ||
			strings.HasPrefix(remoteIP, "::1") ||
			strings.HasPrefix(remoteIP, "[::1]")

		if !isLocal {
			// Remote client — give them the public IP or tunnel URL
			turnTunnelMu.RLock()
			tURL := turnTunnelURL
			turnTunnelMu.RUnlock()

			if tURL != "" {
				iceServers = append(iceServers, map[string]interface{}{
					"urls":       tURL,
					"username":   turnUsername,
					"credential": turnPassword,
				})
			}
		}
		log.Printf("[turn] Serving embedded TURN to %s (local=%v)", remoteIP, isLocal)
	}

	// Also add TURN servers from environment if configured (override)
	envTurnURL := os.Getenv("TURN_URL")
	envTurnUser := os.Getenv("TURN_USERNAME")
	envTurnCred := os.Getenv("TURN_CREDENTIAL")
	if envTurnURL != "" && envTurnUser != "" && envTurnCred != "" {
		iceServers = append(iceServers, map[string]interface{}{
			"urls":       envTurnURL,
			"username":   envTurnUser,
			"credential": envTurnCred,
		})
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"iceServers": iceServers,
	})
}

func handleGetRoom(w http.ResponseWriter, r *http.Request) {
	code := mux.Vars(r)["code"]
	room := roomManager.GetRoom(code)
	w.Header().Set("Content-Type", "application/json")
	if room == nil {
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "room not found"})
	} else {
		json.NewEncoder(w).Encode(map[string]interface{}{"code": room.Code, "host": room.Host})
	}
}

func handleJoinPage(w http.ResponseWriter, r *http.Request) {
	code := mux.Vars(r)["code"]
	room := roomManager.GetRoom(code)

	tunnelMu.RLock()
	tURL := tunnelURL
	tunnelMu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	if room == nil {
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "room not found", "code": code})
	} else {
		json.NewEncoder(w).Encode(map[string]interface{}{"code": room.Code, "host": room.Host, "tunnel": tURL})
	}
}

func handleGetReadyCount(w http.ResponseWriter, r *http.Request) {
	code := mux.Vars(r)["code"]
	room := roomManager.GetRoom(code)
	w.Header().Set("Content-Type", "application/json")
	if room == nil {
		fmt.Fprintf(w, `{"error":"room not found"}`)
		return
	}
	room.mu.RLock()
	count := len(room.ReadyViewers)
	room.mu.RUnlock()
	fmt.Fprintf(w, `{"readyCount":%d}`, count)
}

// ── Cloudflare Tunnel ────────────────────────────────────────────────────────

var tunnelReadyCh = make(chan struct{}, 1)

func startCloudflaredTunnel(port int) {
	cloudflaredCmdMu.Lock()
	if shuttingDown {
		cloudflaredCmdMu.Unlock()
		return
	}
	cloudflaredCmdMu.Unlock()

	cfPath, err := findOrDownloadCloudflared()
	if err != nil {
		log.Printf("cloudflared not available: %v", err)
		return
	}

	cmd := exec.Command(cfPath, "tunnel", "--url", fmt.Sprintf("http://127.0.0.1:%d", port))
	cmd.Env = os.Environ()

	stderr, err := cmd.StderrPipe()
	if err != nil {
		log.Printf("Failed to get cloudflared stderr: %v", err)
		return
	}

	if err := cmd.Start(); err != nil {
		log.Printf("Failed to start cloudflared: %v", err)
		return
	}

	cloudflaredCmdMu.Lock()
	cloudflaredCmd = cmd
	cloudflaredCmdMu.Unlock()

	scanner := bufio.NewScanner(stderr)
	var wg sync.WaitGroup
	wg.Add(1)

	go func() {
		defer wg.Done()
		re := regexp.MustCompile(`https://[a-zA-Z0-9-]+\.trycloudflare\.com`)
		for scanner.Scan() {
			line := scanner.Text()
			log.Printf("cloudflared: %s", line)

			if strings.Contains(line, "trycloudflare.com") {
				match := re.FindString(line)
				if match != "" {
					tunnelMu.Lock()
					tunnelURL = match
					tunnelMu.Unlock()

					log.Printf("Tunnel ready: %s", match)
					select {
					case tunnelReadyCh <- struct{}{}:
					default:
					}
					return
				}
			}
		}
	}()

	wg.Wait()
	if err := cmd.Wait(); err != nil {
		log.Printf("cloudflared exited: %v", err)
	}

	cloudflaredCmdMu.Lock()
	if cloudflaredCmd == cmd {
		cloudflaredCmd = nil
	}
	shouldRestart := !shuttingDown
	cloudflaredCmdMu.Unlock()

	if shouldRestart {
		tunnelMu.Lock()
		tunnelURL = ""
		tunnelMu.Unlock()
		log.Println("Cloudflare tunnel closed; restarting in 2s")
		time.Sleep(2 * time.Second)
		go startCloudflaredTunnel(port)
		return
	}

	log.Println("Cloudflare tunnel closed")
}

func stopCloudflaredTunnel() {
	cloudflaredCmdMu.Lock()
	shuttingDown = true
	cmd := cloudflaredCmd
	cloudflaredCmdMu.Unlock()

	if cmd == nil || cmd.Process == nil {
		return
	}

	if runtime.GOOS == "windows" {
		_ = exec.Command("taskkill", "/PID", strconv.Itoa(cmd.Process.Pid), "/T", "/F").Run()
	} else {
		_ = cmd.Process.Signal(syscall.SIGTERM)
	}
}

func findOrDownloadCloudflared() (string, error) {
	// First check if cloudflared is bundled in the same directory
	exePath, err := os.Executable()
	if err == nil {
		exeDir := filepath.Dir(exePath)
		bundledPath := filepath.Join(exeDir, "cloudflared.exe")
		if runtime.GOOS != "windows" {
			bundledPath = filepath.Join(exeDir, "cloudflared")
		}
		if _, err := os.Stat(bundledPath); err == nil {
			log.Printf("Found bundled cloudflared: %s", bundledPath)
			return bundledPath, nil
		}
	}

	// Then check if cloudflared is in PATH
	path, err := exec.LookPath("cloudflared")
	if err == nil {
		log.Printf("Found cloudflared in PATH: %s", path)
		return path, nil
	}

	// Determine OS-specific paths and download URL
	var binaryName, downloadURL, downloadDir string

	switch runtime.GOOS {
	case "darwin":
		binaryName = "cloudflared"
		homeDir := os.Getenv("HOME")
		downloadDir = filepath.Join(homeDir, ".sharestream")
		if runtime.GOARCH == "arm64" {
			downloadURL = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64"
		} else {
			downloadURL = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64"
		}
	case "linux":
		binaryName = "cloudflared"
		homeDir := os.Getenv("HOME")
		downloadDir = filepath.Join(homeDir, ".sharestream")
		downloadURL = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
	case "windows":
		binaryName = "cloudflared.exe"
		appData := os.Getenv("APPDATA")
		if appData != "" {
			downloadDir = filepath.Join(appData, "sharestream")
		} else {
			downloadDir = "."
		}
		downloadURL = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
	default:
		return "", fmt.Errorf("cloudflared not found in PATH and auto-download not supported for %s/%s", runtime.GOOS, runtime.GOARCH)
	}

	if err := os.MkdirAll(downloadDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create download dir: %v", err)
	}

	localPath := filepath.Join(downloadDir, binaryName)
	if _, err := os.Stat(localPath); err == nil {
		log.Printf("Using cached cloudflared at: %s", localPath)
		return localPath, nil
	}

	log.Printf("cloudflared not found, downloading from %s to %s...", downloadURL, localPath)

	resp, err := http.Get(downloadURL)
	if err != nil {
		return "", fmt.Errorf("failed to download cloudflared: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("failed to download cloudflared: status %d", resp.StatusCode)
	}

	out, err := os.Create(localPath)
	if err != nil {
		return "", fmt.Errorf("failed to create cloudflared file at %s: %v", localPath, err)
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	if err != nil {
		os.Remove(localPath)
		return "", fmt.Errorf("failed to save cloudflared: %v", err)
	}

	// Make executable on Unix systems
	if runtime.GOOS != "windows" {
		os.Chmod(localPath, 0755)
	}

	log.Printf("cloudflared downloaded to: %s", localPath)
	return localPath, nil
}

// ── Embedded TURN Server ─────────────────────────────────────────────────────

func startEmbeddedTURN(port int) error {
	// Listen on both UDP and TCP for maximum compatibility
	udpAddr := fmt.Sprintf("0.0.0.0:%d", port)
	tcpAddr := fmt.Sprintf("0.0.0.0:%d", port)

	// UDP listener
	udpListener, err := net.ListenPacket("udp4", udpAddr)
	if err != nil {
		log.Printf("[turn] UDP listen failed on %s: %v — trying TCP only", udpAddr, err)
		udpListener = nil
	}

	// TCP listener
	tcpListener, err := net.Listen("tcp4", tcpAddr)
	if err != nil {
		log.Printf("[turn] TCP listen failed on %s: %v", tcpAddr, err)
		if udpListener == nil {
			return fmt.Errorf("both UDP and TCP listen failed for TURN on port %d", port)
		}
	}

	logFactory := pionLogging.NewDefaultLoggerFactory()
	logFactory.DefaultLogLevel = pionLogging.LogLevelInfo

	// Build the TURN server config
	cfg := turn.ServerConfig{
		Realm: "sharestream",
		AuthHandler: func(username, realm string, srcAddr net.Addr) ([]byte, bool) {
			if username == turnUsername {
				return turn.GenerateAuthKey(turnUsername, "sharestream", turnPassword), true
			}
			return nil, false
		},
		LoggerFactory: logFactory,
	}

	if udpListener != nil {
		cfg.PacketConnConfigs = []turn.PacketConnConfig{
			{
				PacketConn: udpListener,
				RelayAddressGenerator: &turn.RelayAddressGeneratorStatic{
					RelayAddress: net.ParseIP("0.0.0.0"),
					Address:      "0.0.0.0",
				},
			},
		}
		log.Printf("[turn] UDP listener on %s", udpAddr)
	}

	if tcpListener != nil {
		cfg.ListenerConfigs = []turn.ListenerConfig{
			{
				Listener: tcpListener,
				RelayAddressGenerator: &turn.RelayAddressGeneratorStatic{
					RelayAddress: net.ParseIP("0.0.0.0"),
					Address:      "0.0.0.0",
				},
			},
		}
		log.Printf("[turn] TCP listener on %s", tcpAddr)
	}

	s, err := turn.NewServer(cfg)
	if err != nil {
		return fmt.Errorf("failed to create TURN server: %w", err)
	}

	turnServer = s
	log.Printf("[turn] ✅ Embedded TURN server started on port %d (UDP+TCP)", port)
	log.Printf("[turn]    Credentials: user=%s", turnUsername)
	return nil
}

// ── Torrent Peer Exchange ────────────────────────────────────────────────────

func handleTorrentPeerExchange(s *socket.Socket, data map[string]interface{}) {
	log.Printf("[pex] Torrent peer info from %s: %+v", s.Id(), data)

	// Get sender's participant ID
	participantMu.RLock()
	myParticipantID := socketToParticipant[string(s.Id())]
	participantMu.RUnlock()
	if myParticipantID == "" {
		myParticipantID = string(s.Id())
	}

	// Add sender identity to the data
	data["from"] = myParticipantID

	// Broadcast to all rooms the client is in (excluding personal rooms)
	for _, room := range s.Rooms().Keys() {
		if room == socket.Room(s.Id()) || room == socket.Room(myParticipantID) {
			continue
		}
		log.Printf("[pex] Broadcasting torrent peer info to room %s", room)
		s.To(room).Emit("torrent-peer-info", data)
	}
}

// ── Utilities ────────────────────────────────────────────────────────────────

func generateRandomString(length int) string {
	const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	result := make([]byte, length)
	for i := range result {
		result[i] = chars[rand.Intn(len(chars))]
	}
	return string(result)
}

func generateRoomCode() string {
	const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	result := make([]byte, 6)
	for i := range result {
		result[i] = chars[rand.Intn(len(chars))]
	}
	return string(result)
}

func inviteSecret() string {
	secret := os.Getenv("INVITE_SECRET")
	if secret != "" {
		return secret
	}
	return "sharestream-default-dev-secret-change-me"
}

func makeInviteToken(roomCode string) string {
	expiresAt := time.Now().Add(inviteTokenTTL).Unix()
	payload := roomCode + ":" + strconv.FormatInt(expiresAt, 10)
	h := hmac.New(sha256.New, []byte(inviteSecret()))
	h.Write([]byte(payload))
	sig := base64.RawURLEncoding.EncodeToString(h.Sum(nil))
	encodedPayload := base64.RawURLEncoding.EncodeToString([]byte(payload))
	return encodedPayload + "." + sig
}

func validateInviteToken(roomCode, token string) bool {
	if token == "" {
		return false
	}
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return false
	}
	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return false
	}
	payload := string(payloadBytes)
	payloadParts := strings.Split(payload, ":")
	if len(payloadParts) != 2 {
		return false
	}
	payloadRoom := payloadParts[0]
	expiresAt, err := strconv.ParseInt(payloadParts[1], 10, 64)
	if err != nil {
		return false
	}
	if payloadRoom != roomCode {
		return false
	}
	if time.Now().Unix() > expiresAt {
		return false
	}
	h := hmac.New(sha256.New, []byte(inviteSecret()))
	h.Write([]byte(payload))
	expectedSig := base64.RawURLEncoding.EncodeToString(h.Sum(nil))
	return hmac.Equal([]byte(parts[1]), []byte(expectedSig))
}
