# UI URL Display Fix

## Problem
The UI was showing `localhost:3001` in settings, which confused users. They expected to see the tunnel URL that can be shared with viewers.

## Solution
Now the UI shows:
1. **Settings Panel**: Shows the **tunnel URL** (for sharing) with a note that host uses localhost
2. **Server Status Dialog**: Shows the **share URL** (tunnel if available)
3. **Room Code Copy**: Copies the **tunnel URL** with room code

## What the User Sees

### Host Experience:
1. Opens app → Settings shows:
   ```
   Share URL (for viewers): https://jam-picnic-vessel-island.trycloudflare.com
   Host connects via: localhost:3001
   ```

2. Clicks "Host Room" → Room opens

3. Clicks room code badge → Copies:
   ```
   https://jam-picnic-vessel-island.trycloudflare.com#M4QD11
   ```

### Viewer Experience:
1. Receives link: `https://jam-picnic-vessel-island.trycloudflare.com#M4QD11`
2. Pastes in "Join Room" field
3. App connects to tunnel URL
4. Both in same room!

## Technical Details

| Component | Displays | Purpose |
|-----------|----------|---------|
| `_serverController.text` | `http://localhost:3001` | Internal - host connection |
| `_tunnelUrl` | `https://xxx.trycloudflare.com` | Internal - sharing with viewers |
| Settings Panel | Tunnel URL | User sees what to share |
| Server Status | `provider.shareUrl` | Tunnel if available |
| Copy Room Code | `provider.shareUrl` | Tunnel URL for viewers |

## Files Modified

1. `lib/screens/home_screen.dart`
   - `_buildSettingsPanel()` now shows tunnel URL with explanatory text

2. `lib/widgets/server_status_dialog.dart`
   - Shows `shareUrl` instead of torrent serverUrl
   - Uses Consumer to react to provider changes

3. `lib/widgets/top_bar_widget.dart` (already done)
   - Uses `provider.shareUrl` for copying room link

## Testing

After full restart (`flutter clean && flutter run`):

1. **Host** opens app
2. Check Settings panel shows tunnel URL, not localhost
3. Click "Host Room"
4. Click room code → should copy tunnel URL
5. **Viewer** pastes link on different machine
6. Both should connect successfully
