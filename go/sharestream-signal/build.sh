#!/bin/bash

# Build script for sharestream-signal
# Usage: ./build.sh [windows|darwin|linux]

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNAL_DIR="$PROJECT_ROOT/sharestream-signal"
OUTPUT_DIR="$PROJECT_ROOT/bin"

mkdir -p "$OUTPUT_DIR"

build() {
    local os=$1
    local arch=$2
    local ext=""

    echo "Building for $os/$arch..."

    if [ "$os" = "windows" ]; then
        ext=".exe"
    fi

    GOOS=$os GOARCH=$arch go build -o "$OUTPUT_DIR/sharestream-signal-$os-$arch$ext" ./cmd/main.go

    if [ "$os" = "windows" ]; then
        cp "$OUTPUT_DIR/sharestream-signal-windows-amd64.exe" "$OUTPUT_DIR/sharestream-signal.exe"
    fi
}

case "${1:-all}" in
    windows)
        build windows amd64
        ;;
    darwin)
        build darwin amd64
        build darwin arm64
        ;;
    linux)
        build linux amd64
        ;;
    all)
        build windows amd64
        build darwin amd64
        build darwin arm64
        build linux amd64
        ;;
    *)
        echo "Usage: $0 [windows|darwin|linux|all]"
        exit 1
        ;;
esac

echo "Build complete!"
ls -la "$OUTPUT_DIR"
