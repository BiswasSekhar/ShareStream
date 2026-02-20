package engine

import (
	"encoding/hex"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/bencode"
	"github.com/anacrolix/torrent/metainfo"
)

type TorrentEngine struct {
	client   *torrent.Client
	dataDir  string
	torrents map[string]*torrent.Torrent
	mu       sync.RWMutex
	logger   *slog.Logger
}

func New(dataDir string, port int, logger *slog.Logger) (*TorrentEngine, error) {
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create data dir: %w", err)
	}

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = dataDir
	cfg.ListenPort = port
	cfg.NoDHT = false
	cfg.Seed = true

	client, err := torrent.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create torrent client: %w", err)
	}

	engine := &TorrentEngine{
		client:   client,
		dataDir:  dataDir,
		torrents: make(map[string]*torrent.Torrent),
		logger:   logger,
	}

	return engine, nil
}

func (e *TorrentEngine) CreateTorrentFromFile(filePath string) (string, *metainfo.MetaInfo, error) {
	info := metainfo.Info{
		PieceLength: 256 * 1024,
	}

	if err := info.BuildFromFilePath(filePath); err != nil {
		return "", nil, fmt.Errorf("failed to build info from file: %w", err)
	}

	info.Name = filepath.Base(filePath)

	infoBytes, err := bencode.Marshal(info)
	if err != nil {
		return "", nil, fmt.Errorf("failed to bencode info: %w", err)
	}

	mi := &metainfo.MetaInfo{
		InfoBytes: infoBytes,
	}

	mi.AnnounceList = [][]string{
		{"udp://tracker.opentrackr.org:1337/announce"},
		{"udp://tracker.openbittorrent.com:6969/announce"},
	}

	t, err := e.client.AddTorrent(mi)
	if err != nil {
		return "", nil, fmt.Errorf("failed to add torrent: %w", err)
	}

	infoHash := t.InfoHash().HexString()
	e.mu.Lock()
	e.torrents[infoHash] = t
	e.mu.Unlock()

	go func() {
		<-t.GotInfo()
		t.DownloadAll()
	}()

	return infoHash, mi, nil
}

func (e *TorrentEngine) AddMagnet(magnetURI string) (string, error) {
	// Validate magnet URI format
	if !strings.HasPrefix(magnetURI, "magnet:?") {
		return "", fmt.Errorf("invalid magnet URI: must start with 'magnet:?'")
	}
	if !strings.Contains(magnetURI, "xt=urn:btih:") {
		return "", fmt.Errorf("invalid magnet URI: missing info hash (xt=urn:btih:)")
	}

	t, err := e.client.AddMagnet(magnetURI)
	if err != nil {
		return "", fmt.Errorf("failed to add magnet: %w", err)
	}

	infoHash := t.InfoHash().HexString()
	e.mu.Lock()
	e.torrents[infoHash] = t
	e.mu.Unlock()

	go func() {
		<-t.GotInfo()
		t.DownloadAll()
	}()

	return infoHash, nil
}

func (e *TorrentEngine) AddTorrentFile(torrentPath string) (string, error) {
	mi, err := metainfo.LoadFromFile(torrentPath)
	if err != nil {
		return "", fmt.Errorf("failed to load torrent file: %w", err)
	}

	t, err := e.client.AddTorrent(mi)
	if err != nil {
		return "", fmt.Errorf("failed to add torrent: %w", err)
	}

	infoHash := t.InfoHash().HexString()
	e.mu.Lock()
	e.torrents[infoHash] = t
	e.mu.Unlock()

	go func() {
		<-t.GotInfo()
		t.DownloadAll()
	}()

	return infoHash, nil
}

func (e *TorrentEngine) GetTorrent(infoHash string) *torrent.Torrent {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.torrents[infoHash]
}

func (e *TorrentEngine) ListTorrents() []string {
	e.mu.RLock()
	defer e.mu.RUnlock()

	hashes := make([]string, 0, len(e.torrents))
	for hash := range e.torrents {
		hashes = append(hashes, hash)
	}
	return hashes
}

func (e *TorrentEngine) GetTorrentInfo(infoHash string) (map[string]interface{}, error) {
	t := e.GetTorrent(infoHash)
	if t == nil {
		return nil, fmt.Errorf("torrent not found")
	}

	<-t.GotInfo()

	info := t.Info()
	if info == nil {
		return nil, fmt.Errorf("torrent info not available")
	}

	files := t.Files()
	fileList := make([]map[string]interface{}, len(files))
	for i, f := range files {
		fileList[i] = map[string]interface{}{
			"path":      f.Path(),
			"length":    f.Length(),
			"completed": f.BytesCompleted(),
		}
	}

	return map[string]interface{}{
		"name":         t.Name(),
		"infoHash":     infoHash,
		"totalBytes":   t.Length(),
		"bytesDone":    t.BytesCompleted(),
		"bytesMissing": t.BytesMissing(),
		"files":        fileList,
		"numPieces":    t.NumPieces(),
		"complete":     t.Complete().Bool(),
		"seeding":      t.Seeding(),
	}, nil
}

func (e *TorrentEngine) GetTorrentStats(infoHash string) (map[string]interface{}, error) {
	t := e.GetTorrent(infoHash)
	if t == nil {
		return nil, fmt.Errorf("torrent not found")
	}

	stats := t.Stats()

	return map[string]interface{}{
		"activePeers":  stats.ActivePeers,
		"totalPeers":   stats.TotalPeers,
		"pendingPeers": stats.PendingPeers,
		"bytesRead":    stats.BytesRead.Int64(),
		"bytesWritten": stats.BytesWritten.Int64(),
	}, nil
}

func (e *TorrentEngine) ReadFile(infoHash string, filePath string, offset, length int64) (io.ReadCloser, error) {
	t := e.GetTorrent(infoHash)
	if t == nil {
		return nil, fmt.Errorf("torrent not found")
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
		return nil, fmt.Errorf("file not found in torrent")
	}

	reader := file.NewReader()
	if offset > 0 {
		_, err := reader.Seek(offset, io.SeekStart)
		if err != nil {
			reader.Close()
			return nil, fmt.Errorf("failed to seek: %w", err)
		}
	}

	return &readerWrapper{Reader: reader, Closer: reader, limit: length, read: 0}, nil
}

type readerWrapper struct {
	io.Reader
	io.Closer
	limit int64
	read  int64
}

func (rw *readerWrapper) Read(p []byte) (n int, err error) {
	if rw.limit > 0 {
		remaining := rw.limit - rw.read
		if remaining <= 0 {
			return 0, io.EOF
		}
		if int64(len(p)) > remaining {
			p = p[:remaining]
		}
	}
	n, err = rw.Reader.Read(p)
	rw.read += int64(n)
	if err == io.EOF && rw.read < rw.limit {
		return n, nil
	}
	return n, err
}

func (e *TorrentEngine) DropTorrent(infoHash string) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	t, ok := e.torrents[infoHash]
	if !ok {
		return fmt.Errorf("torrent not found")
	}

	t.Drop()
	delete(e.torrents, infoHash)
	return nil
}

func (e *TorrentEngine) CreateMagnetLink(infoHash string) (string, error) {
	t := e.GetTorrent(infoHash)
	if t == nil {
		return "", fmt.Errorf("torrent not found")
	}

	info := t.Info()
	if info == nil {
		return "", fmt.Errorf("torrent info not available")
	}

	ihBytes, _ := hex.DecodeString(infoHash)
	var ih metainfo.Hash
	copy(ih[:], ihBytes)

	_ = ih
	magnetURI := fmt.Sprintf("magnet:?xt=urn:btih:%s&dn=%s", infoHash, info.Name)
	return magnetURI, nil
}

func (e *TorrentEngine) Close() error {
	errs := e.client.Close()
	if len(errs) > 0 {
		return errs[0]
	}
	return nil
}

func (e *TorrentEngine) GetListenPort() int {
	return e.client.LocalPort()
}

func (e *TorrentEngine) GetTorrentName(infoHash string) string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	t, ok := e.torrents[infoHash]
	if !ok {
		return ""
	}
	return t.Name()
}

func (e *TorrentEngine) DropCurrentTorrent() {
	e.mu.Lock()
	defer e.mu.Unlock()
	for _, t := range e.torrents {
		t.Drop()
	}
	e.torrents = make(map[string]*torrent.Torrent)
}

type Info struct {
	Name       string
	ServerURL  string
	Progress   float64
	Peers      int
	Speed      int
	Active     bool
	Complete   bool
}

func (e *TorrentEngine) GetInfo() Info {
	e.mu.RLock()
	defer e.mu.RUnlock()

	info := Info{
		Active: len(e.torrents) > 0,
	}

	if len(e.torrents) > 0 {
		for _, t := range e.torrents {
			info.Name = t.Name()
			stats := t.Stats()
			info.Peers = stats.ActivePeers
			if t.Info() != nil {
				info.Complete = t.Complete().Bool()
				total := t.Length()
				if total > 0 {
					info.Progress = float64(t.BytesCompleted()) / float64(total)
				}
			}
			break // Just get first torrent
		}
	}

	return info
}
