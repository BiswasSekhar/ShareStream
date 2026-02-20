#!/bin/bash

# ShareStream Cross-Platform Launcher
# Usage: ./run.sh [--no-tunnel] [--build-go]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
BUILD_GO=false
NO_TUNNEL=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --build-go)
      BUILD_GO=true
      shift
      ;;
    --no-tunnel)
      NO_TUNNEL=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

echo -e "${BLUE}=== ShareStream Launcher ===${NC}"

# Detect OS
OS="unknown"
GO_BINARY="sharestream-signal"
FLUTTER_DEVICE=""

if [[ "$OSTYPE" == "darwin"* ]]; then
  OS="macos"
  FLUTTER_DEVICE="macos"
  echo -e "${GREEN}Detected: macOS${NC}"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
  OS="windows"
  GO_BINARY="sharestream-signal.exe"
  FLUTTER_DEVICE="windows"
  echo -e "${GREEN}Detected: Windows${NC}"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS="linux"
  FLUTTER_DEVICE="linux"
  echo -e "${GREEN}Detected: Linux${NC}"
else
  echo -e "${YELLOW}Warning: Unknown OS, assuming macOS${NC}"
  OS="macos"
  FLUTTER_DEVICE="macos"
fi

# Check if Go server needs building
GO_DIR="go/sharestream-signal"
GO_SOURCE="$GO_DIR/cmd/main.go"
GO_OUTPUT="$GO_DIR/$GO_BINARY"

if [ "$BUILD_GO" = true ] || [ ! -f "$GO_OUTPUT" ] || [ "$GO_SOURCE" -nt "$GO_OUTPUT" ]; then
  echo -e "${BLUE}Building Go signal server...${NC}"
  
  if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed${NC}"
    exit 1
  fi
  
  cd "$GO_DIR"
  go mod tidy
  go build -o "$GO_BINARY" ./cmd/main.go
  cd ../..
  
  echo -e "${GREEN}✓ Go server built${NC}"
else
  echo -e "${GREEN}✓ Go server is up to date${NC}"
fi

# Check Flutter
echo -e "${BLUE}Checking Flutter...${NC}"
if ! command -v flutter &> /dev/null; then
  echo -e "${RED}Error: Flutter is not installed${NC}"
  exit 1
fi

# Get Flutter dependencies
echo -e "${BLUE}Fetching Flutter dependencies...${NC}"
flutter pub get

# Kill any existing server on port 3001
echo -e "${BLUE}Checking for existing server...${NC}"
if lsof -ti:3001 > /dev/null 2>&1; then
  echo -e "${YELLOW}Killing existing server on port 3001${NC}"
  kill $(lsof -ti:3001) 2>/dev/null || true
  sleep 1
fi

# Start Go server in background
echo -e "${BLUE}Starting signal server...${NC}"

SERVER_ARGS=""
if [ "$NO_TUNNEL" = true ]; then
  SERVER_ARGS="--no-tunnel"
  echo -e "${YELLOW}Tunnel disabled (local only)${NC}"
fi

"$GO_OUTPUT" $SERVER_ARGS &
SERVER_PID=$!

# Cleanup function
cleanup() {
  echo -e "${BLUE}Cleaning up...${NC}"
  kill $SERVER_PID 2>/dev/null || true
  wait $SERVER_PID 2>/dev/null || true
  echo -e "${GREEN}Server stopped${NC}"
}
trap cleanup EXIT INT TERM

# Wait for server to be ready
echo -e "${BLUE}Waiting for server...${NC}"
sleep 2

# Check if server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
  echo -e "${RED}Error: Server failed to start${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Server running (PID: $SERVER_PID)${NC}"

# Run Flutter app
echo -e "${BLUE}Starting Flutter app on $FLUTTER_DEVICE...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

flutter run -d "$FLUTTER_DEVICE" "$@"
