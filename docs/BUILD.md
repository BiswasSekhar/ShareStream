# ShareStream Build Guide

Complete build instructions for all ShareStream components.

## Prerequisites

### All Platforms
- Git
- Go 1.21 or later
- Flutter SDK 3.x

### Platform-Specific

#### Windows
- Visual Studio 2022 with C++ workload
- Windows 10 SDK
- GCC (via MSYS2 or MinGW)

#### macOS
- Xcode 14+
- Command Line Tools: `xcode-select --install`

#### Linux
- GCC/Clang
- GTK development headers
- pkg-config

## Project Structure

```
ShareStream/
├── lib/                      # Flutter app
├── go/
│   ├── sharestream-engine/   # P2P torrent engine
│   └── sharestream-signal/   # Signaling server
├── pubspec.yaml
└── .env                      # Environment config
```

## Build ShareStream-Engine

The engine is a Go binary that handles P2P torrent operations.

### Windows

```powershell
# Navigate to engine directory
cd go\sharestream-engine

# Build for current platform
go build -o sharestream-engine.exe .\cmd

# Build for release (static where possible)
go build -ldflags="-s -w" -o sharestream-engine.exe .\cmd
```

### macOS

```bash
cd go/sharestream-engine

# Build for current platform (Intel or Apple Silicon)
go build -o sharestream-engine ./cmd

# Build universal binary (both architectures)
GOOS=darwin GOARCH=amd64 go build -o sharestream-engine-amd64 ./cmd
GOOS=darwin GOARCH=arm64 go build -o sharestream-engine-arm64 ./cmd
lipo -create -output sharestream-engine sharestream-engine-amd64 sharestream-engine-arm64
```

### Linux

```bash
cd go/sharestream-engine

# Build for current platform
go build -o sharestream-engine ./cmd

# Build static binary
go build -ldflags="-s -w -extldflags=-static" -o sharestream-engine ./cmd
```

### Cross-Compilation Script

Save as `build-engine.sh`:

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/go/sharestream-engine"
mkdir -p ../../bin

echo "Building for Windows AMD64..."
GOOS=windows GOARCH=amd64 CGO_ENABLED=1 \
  go build -ldflags="-s -w" -o ../../bin/sharestream-engine-windows-amd64.exe ./cmd

echo "Building for macOS AMD64..."
GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 \
  go build -ldflags="-s -w" -o ../../bin/sharestream-engine-darwin-amd64 ./cmd

echo "Building for macOS ARM64..."
GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 \
  go build -ldflags="-s -w" -o ../../bin/sharestream-engine-darwin-arm64 ./cmd

echo "Building for Linux AMD64..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=1 \
  go build -ldflags="-s -w" -o ../../bin/sharestream-engine-linux-amd64 ./cmd

echo "Build complete!"
```

## Build ShareStream-Signal

The signal server handles WebSocket connections and room management.

### Build

```bash
cd go/sharestream-signal

# Build for current platform
go build -o sharestream-signal ./cmd

# Build optimized binary
go build -ldflags="-s -w" -o sharestream-signal ./cmd
```

### Docker Build

```bash
cd go/sharestream-signal

# Build image
docker build -t sharestream-signal:latest .

# Run locally
docker run -p 3001:3001 sharestream-signal:latest

# With TURN credentials
docker run -p 3001:3001 \
  -e TURN_URL=turn:your-turn-server.com:3478 \
  -e TURN_USER=username \
  -e TURN_PASS=password \
  sharestream-signal:latest
```

### Deploy to Koyeb

1. **Push to GitHub**:
```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/yourusername/sharestream-signal.git
git push -u main
```

2. **Create Koyeb App**:
   - Go to [koyeb.com](https://koyeb.com)
   - Click "Create App"
   - Select GitHub source
   - Choose your repository

3. **Configure**:
   - **Builder**: Docker
   - **Port**: 3001
   - **Environment Variables** (optional):
     - `TURN_URL`
     - `TURN_USER`
     - `TURN_PASS`

4. **Deploy**: Click "Deploy"

## Build Flutter App

### Get Dependencies

```bash
flutter pub get
```

### Development Build

```bash
# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Linux
flutter run -d linux
```

### Release Build

#### Windows

```powershell
# Build release
flutter build windows --release

# Output location
# build\windows\x64\runner\Release\sharestream.exe

# Create installer (optional)
# Use Inno Setup or MSIX
```

#### macOS

```bash
# Build release
flutter build macos --release

# Output location
# build/macos/Build/Products/Release/sharestream.app

# Create DMG (optional)
hdiutil create -format UDZO -srcfolder build/macos/Build/Products/Release/sharestream.app sharestream.dmg
```

#### Linux

```bash
# Build release
flutter build linux --release

# Output location
# build/linux/x64/release/bundle/sharestream

# Create AppImage (optional)
# Use appimage-builder
```

### Build for Multiple Platforms

```bash
# Enable desktop platforms
flutter config --enable-windows-desktop
flutter config --enable-macos-desktop
flutter config --enable-linux-desktop

# Build all
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

## Development Workflow

### Running Locally

1. **Start the signal server**:
```bash
cd go/sharestream-signal
go run ./cmd -port 3001
```

2. **Build the engine** (first time only):
```bash
cd go/sharestream-engine
go build -o sharestream-engine.exe ./cmd  # Windows
go build -o sharestream-engine ./cmd      # macOS/Linux
```

3. **Run Flutter app**:
```bash
flutter run -d windows
```

### Environment Configuration

Create `.env` in project root:

```bash
# Server Configuration
SERVER_URL=http://localhost:3001

# TURN Configuration (optional)
TURN_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your_username
TURN_CREDENTIAL=your_password

# Development
DEBUG=true
LOG_LEVEL=debug
```

### Hot Reload

Flutter supports hot reload for UI changes. For Go code changes:

1. Stop the Flutter app
2. Rebuild the engine: `go build ...`
3. Restart the Flutter app

## Distribution

### Windows Installer

Using Inno Setup (`installer.iss`):

```pascal
[Setup]
AppName=ShareStream
AppVersion=1.0.0
DefaultDirName={autopf}\ShareStream
OutputDir=dist

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs
Source: "go\sharestream-engine\sharestream-engine.exe"; DestDir: "{app}\engine"

[Icons]
Name: "{group}\ShareStream"; Filename: "{app}\sharestream.exe"
```

### macOS App Bundle

1. Build the app
2. Sign the app (requires Apple Developer account):
```bash
codesign --force --deep --sign "Developer ID Application: Your Name" sharestream.app
```
3. Notarize (optional but recommended):
```bash
xcrun altool --notarize-app --primary-bundle-id "com.yourcompany.sharestream" \
  --username "your@email.com" --password "@keychain:AC_PASSWORD" \
  --file sharestream.dmg
```

### Linux Package

Create a `.deb` package:

```bash
# Create package structure
mkdir -p sharestream_1.0.0_amd64/DEBIAN
mkdir -p sharestream_1.0.0_amd64/usr/share/sharestream
mkdir -p sharestream_1.0.0_amd64/usr/bin

# Copy files
cp -r build/linux/x64/release/bundle/* sharestream_1.0.0_amd64/usr/share/sharestream/
ln -s /usr/share/sharestream/sharestream sharestream_1.0.0_amd64/usr/bin/sharestream

# Create control file
cat > sharestream_1.0.0_amd64/DEBIAN/control << EOF
Package: sharestream
Version: 1.0.0
Section: video
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: Your Name <your@email.com>
Description: Decentralized P2P video streaming
EOF

# Build package
dpkg-deb --build sharestream_1.0.0_amd64
```

## Troubleshooting

### Build Errors

#### "Could not find sharestream-engine"
- Ensure engine binary is built
- Check path in `torrent_service.dart` `_findEnginePath()`

#### "Failed to load dynamic library"
- Install media_kit dependencies
- Windows: Ensure Visual C++ redistributables installed

#### "Socket connection refused"
- Verify signal server is running
- Check firewall settings
- Verify `SERVER_URL` in `.env`

#### "CGO compilation failed"
- Install GCC/Build tools
- Windows: Use MSYS2 MinGW64
- macOS: Install Xcode Command Line Tools

### Performance Issues

#### Slow video startup
- Check torrent progress (need ~5% to start)
- Verify file format is seekable (MP4 with moov atom)

#### WebRTC connection fails
- Check TURN server configuration
- Verify STUN servers are accessible
- Check firewall allows UDP ports

## Release Checklist

- [ ] Update version in `pubspec.yaml`
- [ ] Build engine for all target platforms
- [ ] Build Flutter app for all target platforms
- [ ] Test fresh install on each platform
- [ ] Test room creation and joining
- [ ] Test video streaming
- [ ] Test WebRTC video calls
- [ ] Update CHANGELOG.md
- [ ] Create GitHub release
- [ ] Upload binaries

## CI/CD (GitHub Actions)

`.github/workflows/build.yml`:

```yaml
name: Build

on:
  push:
    tags:
      - 'v*'

jobs:
  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      
      - name: Build Engine
        run: |
          cd go/sharestream-engine
          go build -o sharestream-engine.exe ./cmd
      
      - name: Build Flutter
        run: flutter build windows --release
      
      - name: Upload
        uses: actions/upload-artifact@v3
        with:
          name: windows-build
          path: build/windows/x64/runner/Release/

  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      
      - name: Build Engine
        run: |
          cd go/sharestream-engine
          go build -o sharestream-engine ./cmd
      
      - name: Build Flutter
        run: flutter build macos --release
      
      - name: Upload
        uses: actions/upload-artifact@v3
        with:
          name: macos-build
          path: build/macos/Build/Products/Release/
```
