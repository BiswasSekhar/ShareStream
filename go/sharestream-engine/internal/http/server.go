package server

import (
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"strings"

	"github.com/anacrolix/torrent"
	"sharestream-engine/internal/engine"
)

type Server struct {
	engine   *engine.TorrentEngine
	logger   *slog.Logger
	http     *http.Server
	listener net.Listener
}

func New(eng *engine.TorrentEngine, addr string, logger *slog.Logger) *Server {
	mux := http.NewServeMux()
	s := &Server{
		engine: eng,
		logger: logger,
	}

	mux.HandleFunc("/stream/", s.handleStream)
	mux.HandleFunc("/torrents", s.handleTorrents)
	mux.HandleFunc("/torrent/", s.handleTorrentInfo)

	s.http = &http.Server{
		Addr:    addr,
		Handler: mux,
	}

	return s
}

func NewWithListener(eng *engine.TorrentEngine, listener net.Listener, logger *slog.Logger) *Server {
	mux := http.NewServeMux()
	s := &Server{
		engine:   eng,
		logger:   logger,
		listener: listener,
	}

	mux.HandleFunc("/stream/", s.handleStream)
	mux.HandleFunc("/torrents", s.handleTorrents)
	mux.HandleFunc("/torrent/", s.handleTorrentInfo)

	s.http = &http.Server{
		Handler: mux,
	}

	return s
}

func (s *Server) handleStream(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/stream/")
	parts := strings.SplitN(path, "/", 2)
	if len(parts) < 2 {
		http.Error(w, "invalid path", http.StatusBadRequest)
		return
	}

	infoHash := parts[0]
	filePath := parts[1]

	t := s.engine.GetTorrent(infoHash)
	if t == nil {
		http.Error(w, "torrent not found", http.StatusNotFound)
		return
	}

	<-t.GotInfo()

	files := t.Files()
	var file *torrent.File
	for _, f := range files {
		if f.Path() == filePath {
			file = f
			break
		}
	}

	if file == nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	reader, err := s.engine.ReadFile(infoHash, filePath, 0, 0)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer reader.Close()

	rangeHeader := r.Header.Get("Range")
	if rangeHeader != "" {
		s.handleRangeRequest(w, r, reader, file.Length(), filePath)
		return
	}

	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.FormatInt(file.Length(), 10))
	w.Header().Set("Accept-Ranges", "bytes")

	io.Copy(w, reader)
}

func (s *Server) handleRangeRequest(w http.ResponseWriter, r *http.Request, reader io.ReadCloser, totalSize int64, filePath string) {
	rangeHeader := r.Header.Get("Range")
	parts := strings.SplitN(rangeHeader, "=", 2)
	if len(parts) != 2 {
		http.Error(w, "invalid range", http.StatusBadRequest)
		return
	}

	rangeParts := strings.SplitN(parts[1], "-", 2)
	start, _ := strconv.ParseInt(rangeParts[0], 10, 64)
	var end int64
	if rangeParts[1] == "" {
		end = totalSize - 1
	} else {
		end, _ = strconv.ParseInt(rangeParts[1], 10, 64)
	}

	if start >= totalSize {
		http.Error(w, "range out of bounds", 416)
		return
	}
	if end >= totalSize {
		end = totalSize - 1
	}

	length := end - start + 1

	seeker, ok := reader.(io.Seeker)
	if !ok {
		http.Error(w, "seeker not available", http.StatusInternalServerError)
		return
	}

	_, err := seeker.Seek(start, io.SeekStart)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.FormatInt(length, 10))
	w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, totalSize))
	w.Header().Set("Accept-Ranges", "bytes")
	w.WriteHeader(http.StatusPartialContent)

	limitedReader := &limitedReader{reader: reader, limit: length}
	io.Copy(w, limitedReader)
}

type limitedReader struct {
	reader io.Reader
	limit  int64
	read   int64
}

func (lr *limitedReader) Read(p []byte) (n int, err error) {
	if lr.read >= lr.limit {
		return 0, io.EOF
	}
	remaining := lr.limit - lr.read
	if int64(len(p)) > remaining {
		p = p[:remaining]
	}
	n, err = lr.reader.Read(p)
	lr.read += int64(n)
	return n, err
}

func (s *Server) handleTorrents(w http.ResponseWriter, r *http.Request) {
	torrents := s.engine.ListTorrents()
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"torrents": %v}`, torrents)
}

func (s *Server) handleTorrentInfo(w http.ResponseWriter, r *http.Request) {
	infoHash := strings.TrimPrefix(r.URL.Path, "/torrent/")
	if infoHash == "" {
		http.Error(w, "info hash required", http.StatusBadRequest)
		return
	}

	info, err := s.engine.GetTorrentInfo(infoHash)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, "%v", info)
}

func (s *Server) Start() error {
	return s.http.ListenAndServe()
}

func (s *Server) StartWithListener() error {
	if s.listener == nil {
		return fmt.Errorf("no listener set")
	}
	return s.http.Serve(s.listener)
}

func (s *Server) Close() error {
	return s.http.Close()
}
