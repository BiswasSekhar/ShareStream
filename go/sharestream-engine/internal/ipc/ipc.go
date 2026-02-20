package ipc

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"os"
	"sync"

	"sharestream-engine/internal/engine"
)

// Flutter-compatible protocol
type Command struct {
	Cmd        string `json:"cmd"`
	FilePath   string `json:"filePath,omitempty"`
	MagnetURI  string `json:"magnetURI,omitempty"`
	TrackerURL string `json:"trackerUrl,omitempty"`
}

type Event struct {
	Event      string  `json:"event"`
	ServerURL  string  `json:"serverUrl,omitempty"`
	MagnetURI  string  `json:"magnetURI,omitempty"`
	Name       string  `json:"name,omitempty"`
	Downloaded float64 `json:"downloaded,omitempty"`
	Speed      int     `json:"speed,omitempty"`
	Peers      int     `json:"peers,omitempty"`
	Message    string  `json:"message,omitempty"`
}

type IPC struct {
	engine   *engine.TorrentEngine
	logger   *slog.Logger
	mu       sync.Mutex
	httpPort int
}

func NewIPC(eng *engine.TorrentEngine, httpPort int, logger *slog.Logger) *IPC {
	return &IPC{
		engine:   eng,
		logger:   logger,
		httpPort: httpPort,
	}
}

func (ipc *IPC) Run() error {
	reader := bufio.NewReader(os.Stdin)
	writer := os.Stdout

	// Send ready event with port info
	ipc.sendEvent(writer, Event{Event: "ready"})

	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err == io.EOF {
				return nil
			}
			ipc.logger.Error("failed to read line", "error", err)
			continue
		}

		var cmd Command
		if err := json.Unmarshal(line, &cmd); err != nil {
			ipc.sendEvent(writer, Event{
				Event:   "error",
				Message: fmt.Sprintf("invalid command: %v", err),
			})
			continue
		}

		go ipc.handleCommand(writer, cmd)
	}
}

func (ipc *IPC) handleCommand(writer *os.File, cmd Command) {
	switch cmd.Cmd {
	case "seed":
		ipc.handleSeed(writer, cmd)
	case "add":
		ipc.handleAdd(writer, cmd)
	case "stop":
		ipc.handleStop(writer)
	case "quit":
		ipc.handleQuit(writer)
	case "info":
		ipc.handleInfo(writer)
	default:
		ipc.sendEvent(writer, Event{
			Event:   "error",
			Message: fmt.Sprintf("unknown command: %s", cmd.Cmd),
		})
	}
}

func (ipc *IPC) handleSeed(writer *os.File, cmd Command) {
	infoHash, mi, err := ipc.engine.CreateTorrentFromFile(cmd.FilePath)
	if err != nil {
		ipc.sendEvent(writer, Event{
			Event:   "error",
			Message: err.Error(),
		})
		return
	}

	magnetURI := ""
	if mi != nil {
		magnetURI = mi.Magnet(nil, nil).String()
	}

	serverURL := fmt.Sprintf("http://localhost:%d/%s", ipc.httpPort, infoHash)
	name := ipc.engine.GetTorrentName(infoHash)

	ipc.sendEvent(writer, Event{
		Event:     "seeding",
		ServerURL: serverURL,
		MagnetURI: magnetURI,
		Name:      name,
	})
}

func (ipc *IPC) handleAdd(writer *os.File, cmd Command) {
	infoHash, err := ipc.engine.AddMagnet(cmd.MagnetURI)
	if err != nil {
		ipc.sendEvent(writer, Event{
			Event:   "error",
			Message: err.Error(),
		})
		return
	}

	serverURL := fmt.Sprintf("http://localhost:%d/%s", ipc.httpPort, infoHash)
	name := ipc.engine.GetTorrentName(infoHash)

	ipc.sendEvent(writer, Event{
		Event:     "added",
		ServerURL: serverURL,
		Name:      name,
	})
}

func (ipc *IPC) handleStop(writer *os.File) {
	ipc.engine.DropCurrentTorrent()
	ipc.sendEvent(writer, Event{Event: "stopped"})
}

func (ipc *IPC) handleQuit(writer *os.File) {
	ipc.engine.Close()
	ipc.sendEvent(writer, Event{Event: "stopped"})
	os.Exit(0)
}

func (ipc *IPC) handleInfo(writer *os.File) {
	info := ipc.engine.GetInfo()
	ipc.sendEvent(writer, Event{
		Event:      "info",
		ServerURL:  info.ServerURL,
		Name:       info.Name,
		Downloaded: info.Progress,
		Peers:      info.Peers,
		Speed:      info.Speed,
	})
}

func (ipc *IPC) sendEvent(writer *os.File, event Event) {
	ipc.mu.Lock()
	defer ipc.mu.Unlock()

	b, err := json.Marshal(event)
	if err != nil {
		ipc.logger.Error("failed to marshal event", "error", err)
		return
	}
	writer.Write(append(b, '\n'))
}

// StartProgressReporter sends periodic progress updates
func (ipc *IPC) StartProgressReporter(writer *os.File) {
	// This would need to be called from main.go with a ticker
}
