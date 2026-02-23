# ShareStream UI Guide

Guide for using and extending ShareStream's UI components.

## Design System

ShareStream uses a **dark glassmorphism** design system with premium gradients.

### Color Palette

```dart
// Brand Colors
const Color primary = Color(0xFF6C5CE7);      // Purple
const Color primaryLight = Color(0xFF8B7CF6);  // Light purple
const Color accent = Color(0xFF00D2FF);        // Cyan
const Color accentAlt = Color(0xFFA855F7);     // Magenta

// Background
const Color bgDeep = Color(0xFF0A0A0F);        // Deepest
const Color bgPrimary = Color(0xFF0F0F1A);     // Primary
const Color bgSurface = Color(0xFF161625);     // Surface
const Color bgCard = Color(0xFF1C1C30);        // Cards
const Color bgElevated = Color(0xFF242440);    // Elevated

// Text
const Color textPrimary = Color(0xFFF1F1F6);   // Primary text
const Color textSecondary = Color(0xFFA0A0B8); // Secondary text
const Color textMuted = Color(0xFF6B6B80);     // Muted text
```

### Gradients

```dart
// Primary gradient (buttons, highlights)
const LinearGradient primaryGradient = LinearGradient(
  colors: [primary, accent],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// Card gradient
const LinearGradient cardGradient = LinearGradient(
  colors: [Color(0xFF1C1C33), Color(0xFF141428)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// Accent text gradient
const LinearGradient accentGradient = LinearGradient(
  colors: [Color(0xFF6C5CE7), Color(0xFF00D2FF)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);
```

## Core Components

### GlassCard

Frosted glass effect card with subtle border.

```dart
GlassCard(
  padding: const EdgeInsets.all(16),
  borderRadius: AppTheme.radiusLarge,
  blur: 12,
  child: YourWidget(),
)
```

**Properties**:
- `padding`: Inner padding
- `borderRadius`: Corner radius (default: 20)
- `blur`: Blur intensity (default: 12)
- `borderColor`: Custom border color
- `onTap`: Click handler

---

### GradientButton

Primary action button with gradient and glow.

```dart
GradientButton(
  label: 'Host Room',
  icon: Icons.add_circle_outline_rounded,
  onPressed: () => createRoom(),
  isLoading: false,
)
```

**Properties**:
- `label` (required): Button text
- `icon`: Leading icon
- `onPressed`: Click handler
- `gradient`: Custom gradient
- `isLoading`: Show loading spinner

---

### GlassTextField

Styled text input with glass effect.

```dart
GlassTextField(
  controller: _textController,
  hintText: 'Enter room code',
  prefixIcon: Icons.tag_rounded,
  textCapitalization: TextCapitalization.characters,
  onSubmitted: (value) => joinRoom(),
)
```

**Properties**:
- `controller` (required): TextEditingController
- `hintText`: Placeholder text
- `prefixIcon`: Leading icon
- `obscureText`: Password field
- `onSubmitted`: Enter key handler

---

### ParticipantAvatar

Circular avatar with colored initials.

```dart
ParticipantAvatar(
  name: 'John Doe',
  isHost: true,
  size: 44,
)
```

**Properties**:
- `name` (required): Display name
- `isHost`: Show host badge
- `size`: Diameter in pixels
- `color`: Custom color (auto-generated from name if null)

---

### ShimmerBox

Loading placeholder with animated shimmer.

```dart
ShimmerBox(
  width: 200,
  height: 100,
  borderRadius: AppTheme.radiusMedium,
)
```

## Screen Layouts

### HomeScreen

Landing page with create/join options.

```
┌─────────────────────────────────────┐
│                                     │
│           [Logo Icon]               │
│           ShareStream               │
│      Watch together, instantly.     │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Your display name           │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │      [ Host Room ]          │    │
│  └─────────────────────────────┘    │
│                                     │
│  ──────────── or ─────────────────  │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Room code or paste link     │    │
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │      [ Join Room ]          │    │
│  └─────────────────────────────┘    │
│                                     │
│       Server Settings ▼             │
│                                     │
└─────────────────────────────────────┘
```

**Features**:
- Auto-detects local server
- Supports ServerURL#RoomCode format
- Animated entrance
- Settings panel (expandable)

---

### RoomScreen

Main video room with player and controls.

```
┌──────────────────────────────────────────────────────────────┐
│ [←] Room: ABC123    [Participants] [Chat] [📹] [Leave]       │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                                                              │
│                    [ Video Player ]                          │
│                                                              │
│                    (or empty state)                          │
│                                                              │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ [▶] 0:00 / 2:30:00 ──────────────── Movie Name.mp4  [⛶]    │
├──────────────────────────────────────────────────────────────┤
│  Participants  │  Chat                                        │
│  ┌──────────┐  │  ┌──────────────────────────────────────┐   │
│  │ JD Host  │  │  │ Alice: Great movie!                  │   │
│  │ Bob      │  │  │ Bob: Yeah!                           │   │
│  │ Alice    │  │  │                                      │   │
│  └──────────┘  │  └──────────────────────────────────────┘   │
│                │  [Type a message...] [Send]                  │
└──────────────────────────────────────────────────────────────┘
```

**Features**:
- Responsive layout (wide/narrow)
- Video call overlay (PIP)
- Playback controls
- Chat panel
- Participants list
- Join request dialogs (for host)

## Animation Patterns

### Entrance Animations

```dart
// Fade in with slide
YourWidget()
  .animate()
  .fadeIn(delay: 200.ms)
  .slideY(begin: 0.15)

// Scale bounce
YourWidget()
  .animate()
  .scale(
    begin: const Offset(0.5, 0.5),
    end: const Offset(1.0, 1.0),
    curve: Curves.elasticOut,
    duration: 800.ms,
  )
```

### Continuous Animations

```dart
// Pulsing glow
YourWidget()
  .animate(onPlay: (c) => c.repeat(reverse: true))
  .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.05, 1.05))
  .shimmer(duration: 2000.ms)
```

## Custom Theme Extensions

### Adding a New Widget Style

```dart
// In lib/theme/app_theme.dart

// Add new color
static const Color myNewColor = Color(0xFF123456);

// Add new gradient
static const LinearGradient myGradient = LinearGradient(
  colors: [myNewColor, accent],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
```

### Using Theme Data

```dart
// Access colors
Container(
  color: AppTheme.bgCard,
  child: Text('Hello', style: TextStyle(color: AppTheme.textPrimary)),
)

// Use text theme
Text(
  'Title',
  style: Theme.of(context).textTheme.headlineLarge,
)
```

## Responsive Design

### Breakpoints

```dart
// LayoutBuilder pattern
LayoutBuilder(
  builder: (context, constraints) {
    final isWide = constraints.maxWidth > 800;
    if (isWide) return _buildWideLayout();
    return _buildNarrowLayout();
  },
)
```

### Common Patterns

```dart
// Compact mode for small screens
final screenHeight = MediaQuery.sizeOf(context).height;
final isCompact = screenHeight < 700;

SizedBox(height: isCompact ? 8 : 16)

// Max width container
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 440),
  child: YourContent(),
)
```

## Dialogs and Overlays

### Join Request Dialog

```dart
void _showJoinRequestDialog(String participantId, String name) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('Join Request', 
        style: TextStyle(color: AppTheme.textPrimary)),
      content: Text('$name wants to join the room.',
        style: const TextStyle(color: AppTheme.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => rejectJoin(participantId),
          child: const Text('Reject', style: TextStyle(color: AppTheme.error)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
          onPressed: () => approveJoin(participantId),
          child: const Text('Approve'),
        ),
      ],
    ),
  );
}
```

### Video Call Overlay

```dart
// Floating PIP overlay
Positioned(
  right: 16,
  bottom: 100,
  width: 240,
  height: 180,
  child: VideoCallOverlay(
    webrtcService: provider.webrtc,
    onEndCall: () => endCall(),
  ),
)
```

## Best Practices

1. **Always use theme constants**: Don't hardcode colors/sizes
2. **Animate intentionally**: Use subtle animations, avoid motion sickness
3. **Handle loading states**: Show shimmer or spinner for async operations
4. **Responsive layouts**: Test on different screen sizes
5. **Accessibility**: Include semantic labels, ensure contrast ratios

## Common Patterns

### Form Validation

```dart
GlassTextField(
  controller: _controller,
  hintText: 'Room code',
  onSubmitted: (value) {
    if (value.isEmpty) {
      _showError('Please enter a room code');
      return;
    }
    joinRoom(value);
  },
)
```

### Loading States

```dart
GradientButton(
  label: isLoading ? 'Loading...' : 'Submit',
  isLoading: isLoading,
  onPressed: isLoading ? null : () => submit(),
)
```

### Error Handling

```dart
void _showError(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppTheme.bgElevated,
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
```
