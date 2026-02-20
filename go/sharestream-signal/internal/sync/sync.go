package sync

import (
	"sync"
	"time"
)

type PlaybackReport struct {
	RoomCode      string
	ParticipantID string
	PlaybackTime  float64
	Playing       bool
	Timestamp     int64
}

type PlaybackState struct {
	Time   float64
	Playing bool
}

type Manager struct {
	mu           sync.RWMutex
	rooms        map[string][]*PlaybackReport
	states       map[string]*PlaybackState
	checkInterval time.Duration
	stopChan     chan bool
}

func New(checkInterval time.Duration) *Manager {
	return &Manager{
		rooms:        make(map[string][]*PlaybackReport),
		states:       make(map[string]*PlaybackState),
		checkInterval: checkInterval,
		stopChan:     make(chan bool),
	}
}

func (m *Manager) Start() {
	go func() {
		ticker := time.NewTicker(m.checkInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				m.processRooms()
			case <-m.stopChan:
				return
			}
		}
	}()
}

func (m *Manager) Stop() {
	close(m.stopChan)
}

func (m *Manager) AddReport(roomCode string, report *PlaybackReport) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if _, exists := m.rooms[roomCode]; !exists {
		m.rooms[roomCode] = make([]*PlaybackReport, 0)
	}

	m.rooms[roomCode] = append(m.rooms[roomCode], report)
}

func (m *Manager) processRooms() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for roomCode, reports := range m.rooms {
		if len(reports) == 0 {
			continue
		}

		state := m.calculateConsensus(reports)
		m.states[roomCode] = state

		m.rooms[roomCode] = m.rooms[roomCode][:0]
	}
}

func (m *Manager) calculateConsensus(reports []*PlaybackReport) *PlaybackState {
	if len(reports) == 0 {
		return &PlaybackState{Time: 0, Playing: false}
	}

	var totalTime float64
	playingCount := 0

	for _, r := range reports {
		totalTime += r.PlaybackTime
		if r.Playing {
			playingCount++
		}
	}

	avgTime := totalTime / float64(len(reports))
	consensusPlaying := playingCount > len(reports)/2

	return &PlaybackState{
		Time:   avgTime,
		Playing: consensusPlaying,
	}
}

func (m *Manager) GetState(roomCode string) *PlaybackState {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if state, exists := m.states[roomCode]; exists {
		return state
	}

	return &PlaybackState{Time: 0, Playing: false}
}

func (m *Manager) GetReports(roomCode string) []*PlaybackReport {
	m.mu.RLock()
	defer m.mu.RUnlock()

	reports := make([]*PlaybackReport, len(m.rooms[roomCode]))
	copy(reports, m.rooms[roomCode])

	return reports
}
