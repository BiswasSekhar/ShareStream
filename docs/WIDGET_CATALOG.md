# ShareStream Widget Catalog

Complete reference of all reusable UI widgets in ShareStream.

## Core Widgets (lib/widgets/common_widgets.dart)

### GlassCard

Frosted glass container with subtle border.

```dart
GlassCard(
  padding: const EdgeInsets.all(16),
  borderRadius: AppTheme.radiusLarge,  // 20
  blur: 12,
  borderColor: Colors.white.withValues(alpha: 0.1),
  onTap: () {},  // Optional tap handler
  child: Column(
    children: [/* content */],
  ),
)
```

**Use cases**: Containers, panels, cards, modals

---

### GradientButton

Primary action button with animated gradient and glow.

```dart
GradientButton(
  label: 'Host Room',
  icon: Icons.add_circle_outline_rounded,
  onPressed: () => createRoom(),
  gradient: AppTheme.primaryGradient,  // Optional custom gradient
  width: double.infinity,  // Optional fixed width
  isLoading: false,  // Show spinner
)
```

**Use cases**: Primary CTAs, submit buttons, important actions

**States**:
- Normal: Gradient with subtle shadow
- Hover: Enhanced glow (desktop)
- Loading: Spinner instead of icon/text
- Disabled: Null onPressed

---

### GlassTextField

Styled text input with glassmorphism effect.

```dart
GlassTextField(
  controller: _controller,
  hintText: 'Enter room code',
  prefixIcon: Icons.tag_rounded,
  obscureText: false,
  textCapitalization: TextCapitalization.characters,
  textInputAction: TextInputAction.go,
  onSubmitted: (value) => joinRoom(value),
  maxLength: 8,
)
```

**Use cases**: Form inputs, search fields, code entry

---

### ParticipantAvatar

Circular avatar with generated color from name.

```dart
ParticipantAvatar(
  name: 'John Doe',
  isHost: true,  // Show host badge
  size: 44,  // Diameter in pixels
  color: AppTheme.primary,  // Optional override
)
```

**Colors**: Auto-generated from name hash (8 preset colors)

**Use cases**: Participant lists, user profiles, chat headers

---

### ShimmerBox

Animated loading placeholder.

```dart
ShimmerBox(
  width: 200,
  height: 100,
  borderRadius: AppTheme.radiusMedium,  // 14
)
```

**Use cases**: Loading states, skeleton screens

---

## Video Widgets (lib/widgets/video_player_widget.dart)

### VideoPlayerWidget

Main video display with play/pause overlay.

```dart
VideoPlayerWidget(
  videoController: _videoController,
  provider: roomProvider,
  videoLoaded: true,
  isPlaying: _isPlaying,
  controlsVisible: _controlsVisible,
  position: _position,
  duration: _duration,
  onTogglePlayPause: () {},
  onToggleControls: () {},
  onPickFile: () {},
  onSeek: (position) {},
  selectedFileName: 'movie.mp4',
)
```

**States**:
- Empty: Shows "Select a video" or "Waiting for host"
- Loaded: Video player with overlay controls
- Controls visible: Play/pause button centered

---

### PlaybackControlsWidget

Bottom bar with seek slider and controls.

```dart
PlaybackControlsWidget(
  videoLoaded: true,
  isPlaying: _isPlaying,
  position: _position,
  duration: _duration,
  onTogglePlayPause: () {},
  onSeek: (position) {},
  selectedFileName: 'movie.mp4',
)
```

**Features**:
- Time display (current / total)
- Seek slider with theme styling
- Play/pause button
- Filename display
- Fullscreen button (placeholder)

---

## Room Widgets

### TopBarWidget (lib/widgets/top_bar_widget.dart)

Room header with controls.

```dart
TopBarWidget(
  provider: roomProvider,
  showParticipants: true,
  showChat: false,
  onLeave: () {},
  onToggleVideoCall: () {},
  onToggleParticipants: () {},
  onToggleChat: () {},
  pendingJoinRequests: 2,  // Badge count
)
```

**Features**:
- Room code display
- Participant/chat toggle buttons
- Video call button
- Leave room button
- Join request badge (host only)

---

### SidePanelWidget (lib/widgets/side_panel_widget.dart)

Right panel with chat and participants.

```dart
SidePanelWidget(
  provider: roomProvider,
  showChat: true,
  showParticipants: true,
  onShowParticipants: () {},
  onShowChat: () {},
  chatController: _chatController,
  chatScrollController: _chatScrollController,
  onSendMessage: () {},
)
```

**Features**:
- Tab switching (Participants / Chat)
- Participant list with avatars
- Chat message list
- Message input field

---

### VideoCallOverlay (lib/widgets/video_call_overlay.dart)

Floating PIP video call widget.

```dart
VideoCallOverlay(
  webrtcService: roomProvider.webrtc,
  onEndCall: () {},
)
```

**Features**:
- Local video preview (small)
- Remote videos (grid)
- Mute/video toggle buttons
- End call button
- Draggable position

---

## Server Widgets (lib/widgets/server_status_dialog.dart)

### ServerStatusDialog

Debug dialog showing server and engine status.

```dart
showDialog(
  context: context,
  builder: (_) => const ServerStatusDialog(),
);
```

**Displays**:
- Engine status (running/stopped)
- Signal server status
- Connection state
- Last error messages

---

## Theme Constants (lib/theme/app_theme.dart)

### Colors

```dart
AppTheme.primary       // Purple #6C5CE7
AppTheme.primaryLight  // Light purple #8B7CF6
AppTheme.accent        // Cyan #00D2FF
AppTheme.success       // Green #22C55E
AppTheme.warning       // Yellow #FBBF24
AppTheme.error         // Red #EF4444

AppTheme.bgDeep        // Deepest background #0A0A0F
AppTheme.bgPrimary     // Primary background #0F0F1A
AppTheme.bgSurface     // Surface #161625
AppTheme.bgCard        // Cards #1C1C30

AppTheme.textPrimary   // Main text #F1F1F6
AppTheme.textSecondary // Secondary text #A0A0B8
AppTheme.textMuted     // Muted text #6B6B80
```

### Spacing

```dart
AppTheme.spacingXS     // 4
AppTheme.spacingSM     // 8
AppTheme.spacingMD     // 16
AppTheme.spacingLG     // 24
AppTheme.spacingXL     // 32
AppTheme.spacing2XL    // 48
```

### Border Radius

```dart
AppTheme.radiusSmall   // 8
AppTheme.radiusMedium  // 14
AppTheme.radiusLarge   // 20
AppTheme.radiusXLarge  // 28
```

### Gradients

```dart
AppTheme.primaryGradient  // Purple → Cyan
AppTheme.accentGradient   // Purple → Cyan (for text)
AppTheme.cardGradient     // Card surface gradient
```

## Animation Patterns

### Entrance Animation

```dart
YourWidget()
  .animate()
  .fadeIn(delay: 200.ms)
  .slideY(begin: 0.15)
```

### Scale Bounce

```dart
YourWidget()
  .animate()
  .scale(
    begin: const Offset(0.5, 0.5),
    end: const Offset(1.0, 1.0),
    curve: Curves.elasticOut,
    duration: 800.ms,
  )
```

### Continuous Pulse

```dart
YourWidget()
  .animate(onPlay: (c) => c.repeat(reverse: true))
  .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.05, 1.05))
  .shimmer(duration: 2000.ms)
```

## Layout Patterns

### Responsive Layout

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final isWide = constraints.maxWidth > 800;
    if (isWide) return _buildWideLayout();
    return _buildNarrowLayout();
  },
)
```

### Max Width Container

```dart
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 440),
  child: YourContent(),
)
```

### Gradient Background

```dart
Container(
  decoration: const BoxDecoration(
    gradient: LinearGradient(
      colors: [AppTheme.bgDeep, AppTheme.bgPrimary, Color(0xFF0D0D1E)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  ),
  child: YourContent(),
)
```

## Creating New Widgets

When adding new widgets:

1. **Use theme constants**: Don't hardcode colors/sizes
2. **Add to appropriate file**: Common widgets go in `common_widgets.dart`
3. **Follow naming**: `DescriptiveWidget` format
4. **Document parameters**: Add DartDoc comments
5. **Include example**: Show usage in widget catalog

### Example Template

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Brief description of what this widget does.
class MyNewWidget extends StatelessWidget {
  /// Required parameter description
  final String title;
  
  /// Optional parameter description
  final VoidCallback? onTap;
  
  const MyNewWidget({
    super.key,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
```
