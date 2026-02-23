# Cloudflare Tunnel Fix Summary

## Problem
The host was trying to connect to the Cloudflare tunnel URL instead of localhost, causing connection failures.

## Solution
The host now uses `localhost:3001` for their own connection, while the tunnel URL is only used for sharing with external viewers.

## Changes Made

### 1. lib/screens/home_screen.dart
- Added `_tunnelUrl` field to store tunnel URL for sharing
- `_detectServerUrl()` now sets `_serverController.text = 'http://localhost:3001'` when tunnel is found
- `_createRoom()` passes both localhost URL and tunnel URL to provider
- Added debug logging to verify correct URLs are used

### 2. lib/providers/room_provider.dart
- Added `_tunnelUrl` field to store tunnel URL for sharing
- Added `shareUrl` getter that returns tunnel URL (for viewers) or server URL
- Updated `setServerUrl()` to accept optional `tunnelUrl` parameter
- Added debug logging

### 3. lib/widgets/top_bar_widget.dart
- Updated `_copyRoomCode()` to use `provider.shareUrl` instead of `provider.serverUrl`
- This ensures the copied link contains the tunnel URL for external viewers

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  HOST COMPUTER                                              │
│  ┌─────────────────┐         ┌───────────────────────┐     │
│  │   ShareStream   │────────▶│  Signal Server        │     │
│  │     (Flutter)   │         │  localhost:3001       │     │
│  │                 │         └───────────┬───────────┘     │
│  │  Connects to:   │                     │                 │
│  │  localhost:3001 │                     ▼                 │
│  └─────────────────┘            ┌─────────────────┐       │
│                                 │   cloudflared   │       │
│                                 │  (creates tunnel)│       │
│                                 └────────┬────────┘       │
└──────────────────────────────────────────┼────────────────┘
                                           │
                              https://xxx.trycloudflare.com
                                           │
┌──────────────────────────────────────────┼────────────────┐
│  VIEWER COMPUTER                         │                │
│  ┌─────────────────┐                     │                │
│  │   ShareStream   │─────────────────────┘                │
│  │     (Flutter)   │         Connects via tunnel         │
│  │                 │                                    │
│  │  Uses tunnel URL│                                    │
│  └─────────────────┘                                    │
└─────────────────────────────────────────────────────────┘
```

## Testing

1. **Full Restart Required**:
   ```powershell
   flutter clean
   flutter pub get
   flutter run -d windows
   ```

2. **Host a Room**:
   - Click "Host Room"
   - Check the debug console:
     - Should see: `HOST will use: http://localhost:3001`
     - Should see: `Tunnel URL available for sharing: https://xxx.trycloudflare.com`

3. **Copy Room Link**:
   - Click the room code badge
   - Should copy: `https://xxx.trycloudflare.com#ROOMCODE`
   - This link is for external viewers

4. **Viewer Joins**:
   - On a different network/computer, paste the link
   - Viewer connects to tunnel URL
   - Both should be in the same room

## Expected Debug Output

```
[home] ==========================================
[home] Tunnel URL available for sharing: https://statistical-equipped-bags-found.trycloudflare.com
[home] HOST will use: http://localhost:3001
[home] ==========================================
[home] ==========================================
[home] Creating room with:
[home]   Server URL (for host): http://localhost:3001
[home]   Tunnel URL (for sharing): https://statistical-equipped-bags-found.trycloudflare.com
[home] ==========================================
[provider] setServerUrl called:
[provider]   _serverUrl = http://localhost:3001
[provider]   _tunnelUrl = https://statistical-equipped-bags-found.trycloudflare.com
[room] createRoom() → connecting to http://localhost:3001
```

## Troubleshooting

If you still see the old behavior:
1. Make sure to **fully restart** the app (not just hot reload)
2. Run `flutter clean` before running again
3. Check that the debug output shows the new log messages
