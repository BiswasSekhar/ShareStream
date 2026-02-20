#!/bin/bash

# Exit on any error
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}1/4 Pulling latest changes from git...${NC}"
git pull

echo -e "${BLUE}2/4 Building Go Signal Server...${NC}"
cd go/sharestream-signal
go mod tidy
go build -o sharestream-signal ./cmd/main.go
cd ../..

echo -e "${BLUE}3/4 Fetching Flutter dependencies...${NC}"
flutter pub get

echo -e "${BLUE}4/4 Running Flutter App (macOS) with verbose logging...${NC}"
# We start the go server in the background and then run flutter
# Trap EXIT to ensure we kill the go server when we exit the script
trap "echo -e '${BLUE}Cleaning up signal server...${NC}'; pkill -f sharestream-signal || true; pkill -f cloudflared || true" EXIT

# Start signal server in background (with tunnel)
cd go/sharestream-signal
./sharestream-signal &
SIGNAL_PID=$!
cd ../..

echo -e "${GREEN}Signal server started (PID: $SIGNAL_PID). Starting Flutter...${NC}"
flutter run -d macos -v
