package server

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/biswa/sharestream-signal/internal/handlers"
	"github.com/biswa/sharestream-signal/internal/models"
	appsync "github.com/biswa/sharestream-signal/internal/sync"
	"github.com/biswa/sharestream-signal/internal/turn"
	socketio "github.com/googollee/go-socket.io"
	"github.com/gorilla/mux"
)

type Options struct {
	Port     int
	TURNURL  string
	TURNUser string
	TURNPass string
}

type Server struct {
	opts        Options
	httpServer  *http.Server
	socketIO    *socketio.Server
	syncManager *appsync.Manager
	turnGen     *turn.Generator
	rooms       *models.RoomManager
	handler     *handlers.Handler
}

func New(opts Options) (*Server, error) {
	rooms := models.NewRoomManager()

	turnGen := turn.New()
	if opts.TURNURL != "" {
		turnGen.SetStaticTURN(opts.TURNURL, opts.TURNUser, opts.TURNPass)
	}

	syncManager := appsync.New(15 * time.Second)

	socketIO, err := socketio.NewServer(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create socket.io server: %w", err)
	}

	handler := handlers.New(socketIO, rooms, syncManager, turnGen)

	srv := &Server{
		opts:        opts,
		socketIO:    socketIO,
		rooms:       rooms,
		syncManager: syncManager,
		turnGen:     turnGen,
		handler:     handler,
	}

	return srv, nil
}

func (s *Server) Start() error {
	s.setupSocketIO()

	router := mux.NewRouter()

	// Create CORS middleware
	corsMiddleware := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
			w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization")

			if r.Method == "OPTIONS" {
				w.WriteHeader(http.StatusNoContent)
				return
			}

			next.ServeHTTP(w, r)
		})
	}

	router.Use(corsMiddleware)
	router.Handle("/socket.io/", s.socketIO)
	router.HandleFunc("/health", s.healthCheck)
	router.HandleFunc("/api/rooms/{code}", s.handler.GetRoom)
	router.HandleFunc("/api/turn/credentials", s.handler.GetTURNCredentials)

	s.httpServer = &http.Server{
		Addr:         fmt.Sprintf(":%d", s.opts.Port),
		Handler:      router,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	}

	go func() {
		if err := s.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("HTTP server error: %v", err)
		}
	}()

	go s.syncManager.Start()

	return nil
}

func (s *Server) Stop() error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if s.httpServer != nil {
		if err := s.httpServer.Shutdown(ctx); err != nil {
			return fmt.Errorf("failed to shutdown http server: %w", err)
		}
	}

	if s.socketIO != nil {
		s.socketIO.Close()
	}

	s.syncManager.Stop()

	return nil
}

func (s *Server) healthCheck(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok","service":"sharestream-signal"}`))
}

func (s *Server) setupSocketIO() {
	s.socketIO.OnConnect("/", func(conn socketio.Conn) error {
		log.Printf("Client connected: %s", conn.ID())
		conn.SetContext("")
		return nil
	})

	s.socketIO.OnDisconnect("/", func(conn socketio.Conn, reason string) {
		log.Printf("Client disconnected: %s, reason: %s", conn.ID(), reason)
		s.handler.HandleDisconnect(conn.ID())
	})

	s.socketIO.OnEvent("/", "create-room", s.handler.HandleCreateRoom)
	s.socketIO.OnEvent("/", "join-room", s.handler.HandleJoinRoom)
	s.socketIO.OnEvent("/", "leave-room", s.handler.HandleLeaveRoom)

	s.socketIO.OnEvent("/", "torrent-magnet", s.handler.HandleTorrentMagnet)
	s.socketIO.OnEvent("/", "movie-loaded", s.handler.HandleMovieLoaded)

	s.socketIO.OnEvent("/", "sync-play", s.handler.HandleSyncPlay)
	s.socketIO.OnEvent("/", "sync-pause", s.handler.HandleSyncPause)
	s.socketIO.OnEvent("/", "sync-seek", s.handler.HandleSyncSeek)

	s.socketIO.OnEvent("/", "chat-message", s.handler.HandleChatMessage)

	s.socketIO.OnEvent("/", "start-webrtc", s.handler.HandleStartWebRTC)
	s.socketIO.OnEvent("/", "offer", s.handler.HandleOffer)
	s.socketIO.OnEvent("/", "answer", s.handler.HandleAnswer)
	s.socketIO.OnEvent("/", "ice-candidate", s.handler.HandleICECandidate)

	s.socketIO.OnEvent("/", "sync-check", s.handler.HandleSyncCheck)
	s.socketIO.OnEvent("/", "sync-report", s.handler.HandleSyncReport)
	s.socketIO.OnEvent("/", "sync-correct", s.handler.HandleSyncCorrect)

	s.socketIO.OnEvent("/", "ready-for-connection", s.handler.HandleReadyForConnection)
}
