package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	"github.com/zishang520/engine.io/v2/types"
	"github.com/zishang520/socket.io/v2/socket"
)

var (
	port     = flag.Int("port", 3001, "Server port")
	noTunnel = flag.Bool("no-tunnel", false, "Disable automatic tunnel creation")

	io_       *socket.Server
	tunnelURL string
	tunnelMu  sync.RWMutex
)

// ── Room Management ──────────────────────────────────────────────────────────

type Room struct {
	Code          string
	Host          string
	Approved      map[string]bool
	Pending       map[string]string
	ApprovedNames map[string]string
	ReadyViewers  map[string]bool
	HostTimestamp time.Time
	HostState     string
	mu            sync.RWMutex
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
	client.On("sync-play", func(args ...any) {
		data := parseData(args)
		handleBroadcastToRooms(client, "sync-play", data)
	})
	client.On("sync-pause", func(args ...any) {
		data := parseData(args)
		handleBroadcastToRooms(client, "sync-pause", data)
	})
	client.On("sync-seek", func(args ...any) {
		data := parseData(args)
		handleBroadcastToRooms(client, "sync-seek", data)
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
		// When a client is ready, notify all other participants to start WebRTC
		for _, room := range client.Rooms().Keys() {
			if room == socket.Room(client.Id()) {
				continue
			}
			// Broadcast to room that this client is ready to connect
			client.To(room).Emit("start-webrtc", map[string]interface{}{
				"peerId":    client.Id(),
				"initiator": true, // Existing participants initiate the connection
			})
			log.Printf("[webrtc] Notified room %s that %s is ready for connection", room, client.Id())
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
	code := generateRoomCode()
	roomManager.CreateRoom(code, string(s.Id()))
	s.Join(socket.Room(code))

	tunnelMu.RLock()
	tURL := tunnelURL
	tunnelMu.RUnlock()

	s.Emit("room-created", map[string]interface{}{
		"success": true,
		"room": map[string]interface{}{
			"code":   code,
			"role":   "host",
			"tunnel": tURL,
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
	io_.To(socket.Room(code)).Emit("participant-joined", map[string]interface{}{
		"id":   participantID,
		"name": name,
	})
}

func handleLeaveRoom(s *socket.Socket, data map[string]interface{}) {
	log.Printf("Leave room: %+v", data)
	code, ok := data["code"].(string)
	if !ok {
		return
	}
	s.Leave(socket.Room(code))
	io_.To(socket.Room(code)).Emit("participant-left", map[string]interface{}{
		"id": string(s.Id()),
	})
}

func handleJoinRequest(s *socket.Socket, data map[string]interface{}) {
	log.Printf("[JOIN] Join request from %s: %+v", s.Id(), data)
	code, ok := data["code"].(string)
	name, nameOk := data["name"].(string)
	participantID, pOk := data["participantId"].(string)
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

	room.mu.Lock()
	room.Pending[participantID] = name
	room.mu.Unlock()

	s.Emit("join-request-result", map[string]interface{}{
		"success":       true,
		"status":        "pending",
		"participantId": participantID,
	})

	// Notify the host
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

	io_.To(socket.Room(code)).Emit("participant-joined", map[string]interface{}{
		"id":   participantID,
		"name": name,
	})
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

	room.mu.RLock()
	_, isApproved := room.Approved[string(s.Id())]
	_, isPending := room.Pending[string(s.Id())]
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
	for _, room := range rooms {
		// Skip the socket's personal ID room (if it exists)
		if room == socket.Room(s.Id()) {
			continue
		}
		log.Printf("[broadcast] Emitting %s to room %s", event, room)
		io_.To(room).Emit(event, data)
	}
}

// handleTargetedEmit sends an event to a specific target socket by ID.
func handleTargetedEmit(s *socket.Socket, event string, data map[string]interface{}) {
	log.Printf("%s: %+v", event, data)
	targetID, ok := data["targetId"].(string)
	if !ok {
		return
	}
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

	participantID, _ := data["participantId"].(string)
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
	if !tOk || !playOk {
		return
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
	fmt.Fprintf(w, `{"iceServers":[{"urls":"stun:stun.l.google.com:19302"},{"urls":"stun:stun1.l.google.com:19302"}]}`)
}

func handleGetRoom(w http.ResponseWriter, r *http.Request) {
	code := mux.Vars(r)["code"]
	room := roomManager.GetRoom(code)
	w.Header().Set("Content-Type", "application/json")
	if room == nil {
		fmt.Fprintf(w, `{"error":"room not found"}`)
	} else {
		fmt.Fprintf(w, `{"code":"%s","host":"%s"}`, room.Code, room.Host)
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
		fmt.Fprintf(w, `{"error":"room not found","code":"%s"}`, code)
	} else {
		fmt.Fprintf(w, `{"code":"%s","host":"%s","tunnel":"%s"}`, room.Code, room.Host, tURL)
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
	cfPath, err := findOrDownloadCloudflared()
	if err != nil {
		log.Printf("cloudflared not available: %v", err)
		return
	}

	cmd := exec.Command(cfPath, "tunnel", "--url", fmt.Sprintf("http://localhost:%d", port))
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
	log.Println("Cloudflare tunnel closed")
}

func findOrDownloadCloudflared() (string, error) {
	// First check if cloudflared is in PATH
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
			downloadURL = "https://github.com/cloudflare/cloudflared/releases/download/2026.2.0/cloudflared-darwin-arm64"
		} else {
			downloadURL = "https://github.com/cloudflare/cloudflared/releases/download/2026.2.0/cloudflared-darwin-amd64"
		}
	case "linux":
		binaryName = "cloudflared"
		homeDir := os.Getenv("HOME")
		downloadDir = filepath.Join(homeDir, ".sharestream")
		downloadURL = "https://github.com/cloudflare/cloudflared/releases/download/2026.2.0/cloudflared-linux-amd64"
	case "windows":
		binaryName = "cloudflared.exe"
		appData := os.Getenv("APPDATA")
		if appData != "" {
			downloadDir = filepath.Join(appData, "sharestream")
		} else {
			downloadDir = "."
		}
		downloadURL = "https://github.com/cloudflare/cloudflared/releases/download/2026.2.0/cloudflared-windows-amd64.exe"
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

// ── Utilities ────────────────────────────────────────────────────────────────

func generateRoomCode() string {
	const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	result := make([]byte, 6)
	for i := range result {
		result[i] = chars[rand.Intn(len(chars))]
	}
	return string(result)
}
