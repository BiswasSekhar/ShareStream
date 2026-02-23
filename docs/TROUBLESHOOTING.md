# ShareStream Troubleshooting Guide

Common issues and their solutions.

## Table of Contents

1. [Engine Issues](#engine-issues)
2. [Signaling Server Issues](#signaling-server-issues)
3. [Playback Issues](#playback-issues)
4. [WebRTC Issues](#webrtc-issues)
5. [Network Issues](#network-issues)
6. [Build Issues](#build-issues)

---

## Engine Issues

### "Could not find sharestream-engine"

**Symptoms**: Error dialog when trying to host or join stream

**Solutions**:

1. **Verify engine binary exists**:
   ```powershell
   # Windows
   dir go\sharestream-engine\*.exe
   
   # macOS/Linux
   ls go/sharestream-engine/sharestream-engine
   ```

2. **Build the engine**:
   ```bash
   cd go/sharestream-engine
   go build -o sharestream-engine.exe ./cmd  # Windows
   go build -o sharestream-engine ./cmd      # macOS/Linux
   ```

3. **Check path in code**:
   Edit `lib/services/torrent_service.dart` and update `_findEnginePath()` to include your build location.

4. **Run engine manually to test**:
   ```powershell
   .\go\sharestream-engine\sharestream-engine.exe -http :42069
   # Should see: {"event":"ready","port":42069}
   ```

---

### "Engine startup timeout"

**Symptoms**: Engine doesn't respond within 10 seconds

**Solutions**:

1. **Check for port conflicts**:
   ```powershell
   # Windows
   netstat -ano | findstr :42069
   
   # Kill conflicting process
   taskkill /PID <pid> /F
   ```

2. **Check firewall/antivirus**:
   - Add exception for `sharestream-engine.exe`
   - Allow outbound connections

3. **Check disk space**:
   - Engine needs space for torrent data (default: `./data`)

---

### "Download not starting"

**Symptoms**: Added magnet URI but no progress updates

**Solutions**:

1. **Verify magnet URI format**:
   - Must start with `magnet:?`
   - Must contain `xt=urn:btih:`

2. **Check tracker URL**:
   - Must be valid WebSocket URL
   - Format: `ws://localhost:3001/`

3. **Verify host is seeding**:
   - Host must have file fully available
   - Check host's peer count

4. **Test with a small file first**:
   - Large files take time to start
   - Try a 10MB test video

---

### "Seeding not working"

**Symptoms**: Seed command succeeds but no magnet returned

**Solutions**:

1. **Verify file path**:
   - Must be absolute path
   - File must exist and be readable

2. **Check file permissions**:
   ```powershell
   # Windows - check file properties
   icacls "C:\path\to\video.mp4"
   
   # macOS/Linux
   ls -la /path/to/video.mp4
   ```

3. **Try different video format**:
   - MP4 with H.264 works best
   - MKV and AVI may have issues

---

## Signaling Server Issues

### "Could not connect to server"

**Symptoms**: Socket connection fails, no room creation

**Solutions**:

1. **Verify server URL**:
   - Must include protocol: `http://` or `https://`
   - Example: `http://localhost:3001`

2. **Check if server is running**:
   ```bash
   curl http://localhost:3001/health
   # Should return: {"status":"ok"}
   ```

3. **Check CORS settings**:
   - Server must allow Flutter origin
   - Default allows all origins (`*`)

4. **Firewall check**:
   ```powershell
   # Windows - allow port 3001
   netsh advfirewall firewall add rule name="ShareStream" dir=in action=allow protocol=TCP localport=3001
   ```

---

### "Room not found"

**Symptoms**: Join request fails with room not found error

**Solutions**:

1. **Verify room code**:
   - Codes are case-sensitive
   - Check for typos

2. **Check room expiration**:
   - Rooms are deleted when empty
   - Host may have left

3. **Verify same server**:
   - Host and viewer must use same `SERVER_URL`
   - Check `.env` file on both sides

---

### "Join request was rejected"

**Symptoms**: Viewer sees rejection after requesting to join

**Solutions**:

1. **Wait for host approval**:
   - Host must click "Approve" in dialog
   - Check if host is still in room

2. **Try again**:
   - Leave and rejoin
   - Generate new room code

---

## Playback Issues

### "Video not playing"

**Symptoms**: Black screen or loading spinner

**Solutions**:

1. **Wait for download**:
   - Need ~5-10% download to start
   - Check progress indicator

2. **Verify format support**:
   - MP4 with H.264: Best support
   - MKV: May have seeking issues
   - AVI: Limited support

3. **Check engine HTTP URL**:
   ```bash
   curl http://localhost:42069/abc123
   # Should return binary data
   ```

4. **Try direct file playback**:
   - Use file picker to play local file
   - Bypasses torrent engine

---

### "Seeking not working"

**Symptoms**: Cannot jump to different positions

**Solutions**:

1. **File must have seekable atoms**:
   - MP4 with `moov` atom at beginning
   - Use Handbrake or ffmpeg to fix:
   ```bash
   ffmpeg -i input.mkv -c copy -movflags +faststart output.mp4
   ```

2. **Wait for more download**:
   - Can only seek within downloaded range
   - Let download progress further

3. **Check HTTP range support**:
   ```bash
   curl -I -H "Range: bytes=0-1023" http://localhost:42069/abc123
   # Should return: HTTP/1.1 206 Partial Content
   ```

---

### "Sync not working"

**Symptoms**: Viewer playback doesn't match host

**Solutions**:

1. **Check latency**:
   - High latency causes sync drift
   - Use wired connection if possible

2. **Manual sync**:
   - Host should pause/play to force sync
   - Seek to reset position

3. **Verify sync events**:
   - Check developer console for event logs
   - Look for `sync-play`, `sync-pause`, `sync-seek` events

---

## WebRTC Issues

### "Video call not connecting"

**Symptoms**: No remote video, call fails to start

**Solutions**:

1. **Check camera/mic permissions**:
   - Windows: Settings → Privacy → Camera/Microphone
   - macOS: System Preferences → Security & Privacy

2. **Verify TURN server** (if behind NAT):
   - Configure in `.env`:
   ```
   TURN_URL=turn:your-server.com:3478
   TURN_USERNAME=user
   TURN_CREDENTIAL=pass
   ```

3. **Check firewall**:
   - Allow UDP ports 3478 (STUN/TURN)
   - Allow UDP ports 10000-20000 (WebRTC)

4. **Test on same network**:
   - Try both devices on same WiFi
   - Rules out NAT issues

---

### "Poor video quality"

**Symptoms**: Frozen, pixelated, or laggy video

**Solutions**:

1. **Reduce resolution**:
   Edit `lib/services/webrtc_service.dart`:
   ```dart
   _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
     'video': {
       'width': {'ideal': 320},
       'height': {'ideal': 240},
       'frameRate': {'ideal': 15},
     },
   });
   ```

2. **Check bandwidth**:
   - WebRTC needs ~1 Mbps per peer
   - Use speed test to verify

3. **Limit number of peers**:
   - Mesh topology doesn't scale
   - Max 4-6 participants recommended

---

### "No audio in video call"

**Symptoms**: Video works but no sound

**Solutions**:

1. **Check audio track enabled**:
   ```dart
   // In webrtc_service.dart
   for (final track in _localStream!.getAudioTracks()) {
     track.enabled = true;
   }
   ```

2. **Verify microphone permission**:
   - Check OS-level permissions
   - Try different microphone

3. **Check mute state**:
   - Click microphone button to unmute
   - Verify `audioEnabled` notifier value

---

## Network Issues

### "Port already in use"

**Symptoms**: Engine fails to bind HTTP server

**Solutions**:

1. **Find and kill process**:
   ```powershell
   # Windows
   netstat -ano | findstr :42069
   taskkill /PID <pid> /F
   
   # macOS/Linux
   lsof -i :42069
   kill -9 <pid>
   ```

2. **Use different port**:
   Edit `torrent_service.dart`:
   ```dart
   Process.start(enginePath, ['-http', ':42070'])
   ```

---

### "Firewall blocking connections"

**Symptoms**: Cannot connect to peers or server

**Solutions**:

1. **Windows Defender Firewall**:
   ```powershell
   # Allow app through firewall
   netsh advfirewall firewall add rule name="ShareStream Engine" dir=in action=allow program="C:\path\to\sharestream-engine.exe"
   netsh advfirewall firewall add rule name="ShareStream Signal" dir=in action=allow program="C:\path\to\sharestream-signal.exe"
   ```

2. **macOS Firewall**:
   - System Preferences → Security & Privacy → Firewall
   - Add Flutter app and engines to allowed list

3. **Router/NAT**:
   - Enable UPnP if available
   - Port forward 6881-6889 for BitTorrent

---

## Build Issues

### "CGO compilation failed"

**Symptoms**: Go build fails with CGO errors

**Solutions**:

1. **Windows - Install MSYS2**:
   ```powershell
   # Install MSYS2 from https://www.msys2.org/
   # Then in MSYS2 terminal:
   pacman -S mingw-w64-x86_64-gcc
   
   # Add to PATH: C:\msys64\mingw64\bin
   ```

2. **macOS - Install Xcode tools**:
   ```bash
   xcode-select --install
   ```

3. **Linux - Install build tools**:
   ```bash
   sudo apt-get install build-essential
   ```

---

### "Flutter build fails"

**Symptoms**: `flutter build` produces errors

**Solutions**:

1. **Clean build**:
   ```bash
   flutter clean
   flutter pub get
   ```

2. **Update Flutter**:
   ```bash
   flutter upgrade
   ```

3. **Check dependencies**:
   ```bash
   flutter doctor
   # Fix any issues reported
   ```

---

### "media_kit plugin errors"

**Symptoms**: Video player doesn't work

**Solutions**:

1. **Run setup**:
   ```bash
   dart run media_kit:setup
   ```

2. **Verify native libraries**:
   - Windows: `mpv-2.dll` should be in build output
   - macOS: Frameworks should be embedded

3. **Rebuild**:
   ```bash
   flutter clean
   flutter pub get
   flutter build <platform>
   ```

---

## Debug Logging

Enable detailed logging to diagnose issues:

### Flutter

```dart
// In main.dart
void main() {
  // Enable debug mode
  debugPrint = (String? message, {int? wrapWidth}) {
    print(message); // Log to console
  };
  
  runApp(const ShareStreamApp());
}
```

### Engine

Engine logs to stderr. View logs:

```powershell
# Windows (PowerShell)
.\sharestream-engine.exe 2> engine.log

# Or view in Flutter logs
# Logs are also written to: %APPDATA%\sharestream\torrent.log
```

### Signal Server

```bash
# Run with verbose logging
go run ./cmd -port 3001 2>&1 | tee server.log
```

---

## Getting Help

If issues persist:

1. Check logs for error messages
2. Verify all components are latest version
3. Test with minimal setup (same machine, local server)
4. Create GitHub issue with:
   - Error messages
   - Log files
   - Steps to reproduce
   - Platform details
