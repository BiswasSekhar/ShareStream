package models

import (
	"sync"
	"time"
)

type RoomManager struct {
	mu    sync.RWMutex
	rooms map[string]*Room
}

type Room struct {
	Code         string
	Host         string
	Participants map[string]*Participant
	CreatedAt    time.Time
	Mu           sync.RWMutex
}

type Participant struct {
	ID       string
	Name     string
	SocketID string
	Role     string
	IsHost   bool
	JoinedAt time.Time
}

func NewRoomManager() *RoomManager {
	return &RoomManager{
		rooms: make(map[string]*Room),
	}
}

func (rm *RoomManager) GetRoom(code string) (*Room, bool) {
	rm.mu.RLock()
	defer rm.mu.RUnlock()
	room, exists := rm.rooms[code]
	return room, exists
}

func (rm *RoomManager) AddRoom(room *Room) {
	rm.mu.Lock()
	defer rm.mu.Unlock()
	rm.rooms[room.Code] = room
}

func (rm *RoomManager) DeleteRoom(code string) {
	rm.mu.Lock()
	defer rm.mu.Unlock()
	delete(rm.rooms, code)
}

func (rm *RoomManager) GetAllRooms() map[string]*Room {
	rm.mu.RLock()
	defer rm.mu.RUnlock()

	// Return a copy of the map to avoid race conditions
	roomsCopy := make(map[string]*Room)
	for k, v := range rm.rooms {
		roomsCopy[k] = v
	}
	return roomsCopy
}
