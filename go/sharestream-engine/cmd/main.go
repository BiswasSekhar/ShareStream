package main

import (
	"context"
	"encoding/json"
	"flag"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"sharestream-engine/internal/engine"
	torrenthttp "sharestream-engine/internal/http"
	"sharestream-engine/internal/ipc"
)

type ProgressEvent struct {
	Event      string  `json:"event"`
	Downloaded float64 `json:"downloaded"`
	Speed      int     `json:"speed"`
	Peers      int     `json:"peers"`
	Name       string  `json:"name,omitempty"`
}

func main() {
	dataDir := flag.String("data-dir", "./data", "Directory for torrent data")
	listenPort := flag.Int("port", 6881, "Torrent client listen port")
	httpAddr := flag.String("http", ":0", "HTTP server address (use :0 for auto-assign)")
	flag.Parse()

	// IMPORTANT: slog goes to stderr so stdout stays clean for IPC JSON
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	}))

	eng, err := engine.New(*dataDir, *listenPort, logger)
	if err != nil {
		logger.Error("failed to create engine", "error", err)
		os.Exit(1)
	}
	defer eng.Close()

	logger.Info("engine started", "port", eng.GetListenPort())

	// Bind HTTP listener to get the actual port (supports :0 auto-assign)
	httpListener, err := net.Listen("tcp", *httpAddr)
	if err != nil {
		logger.Error("failed to bind HTTP listener", "address", *httpAddr, "error", err)
		os.Exit(1)
	}
	actualPort := httpListener.Addr().(*net.TCPAddr).Port
	logger.Info("http listener bound", "port", actualPort)

	httpServer := torrenthttp.NewWithListener(eng, httpListener, logger)

	go func() {
		logger.Info("http server starting", "address", httpListener.Addr().String())
		if err := httpServer.StartWithListener(); err != nil && err != http.ErrServerClosed {
			logger.Error("http server error", "error", err)
		}
	}()

	ipcServer := ipc.NewIPC(eng, actualPort, logger)

	go func() {
		if err := ipcServer.Run(); err != nil {
			logger.Error("IPC error", "error", err)
		}
	}()

	go func() {
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()
		writer := os.Stdout
		for {
			select {
			case <-ticker.C:
				info := eng.GetInfo()
				if info.Active {
					progress := ProgressEvent{
						Event:      "progress",
						Downloaded: info.Progress,
						Speed:      info.Speed,
						Peers:      info.Peers,
						Name:       info.Name,
					}
					b, _ := json.Marshal(progress)
					writer.Write(append(b, '\n'))
				}
			}
		}
	}()

	// Send ready event with the HTTP port
	readyEvent := map[string]interface{}{
		"event": "ready",
		"port":  actualPort,
	}
	readyBytes, _ := json.Marshal(readyEvent)
	os.Stdout.Write(append(readyBytes, '\n'))

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	sig := <-sigChan
	logger.Info("shutting down", "signal", sig)

	_, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := httpServer.Close(); err != nil {
		logger.Error("error closing http server", "error", err)
	}

	logger.Info("shutdown complete")
}
