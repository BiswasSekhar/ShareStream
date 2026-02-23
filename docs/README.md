# ShareStream Documentation

Welcome to the ShareStream documentation. This directory contains comprehensive guides for understanding, building, and extending ShareStream.

## Quick Start

| Document | Purpose |
|----------|---------|
| [Architecture](ARCHITECTURE.md) | System design and data flows |
| [Build Guide](BUILD.md) | Building and deploying |
| [Troubleshooting](TROUBLESHOOTING.md) | Common issues and solutions |

## Protocol Reference

| Document | Purpose |
|----------|---------|
| [Socket Protocol](SOCKET_PROTOCOL.md) | Socket.IO events reference |
| [IPC Protocol](IPC_PROTOCOL.md) | Engine IPC protocol |
| [API Reference](API.md) | REST API endpoints |

## Development Guides

| Document | Purpose |
|----------|---------|
| [UI Guide](UI_GUIDE.md) | Using and extending UI components |

## Project Root Documentation

| Document | Purpose |
|----------|---------|
| [../AGENTS.md](../AGENTS.md) | Agent quick reference |
| [../IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md) | Original implementation plan |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        SHARESTREAM                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Flutter   │  │   Engine    │  │    Signal Server        │  │
│  │   (Dart)    │  │    (Go)     │  │       (Go)              │  │
│  │             │  │             │  │                         │  │
│  │ • UI        │  │ • Torrent   │  │ • Room Management       │  │
│  │ • Providers │  │ • HTTP      │  │ • WebRTC Signaling      │  │
│  │ • Services  │  │ • IPC       │  │ • Chat Relay            │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Technology Stack

### Frontend
- **Framework**: Flutter 3.x
- **State Management**: Provider
- **Video**: media_kit
- **WebRTC**: flutter_webrtc
- **Networking**: socket_io_client
- **Animations**: flutter_animate

### Backend
- **Language**: Go 1.21+
- **Torrent**: anacrolix/torrent
- **WebSocket**: zishang520/socket.io
- **HTTP**: gorilla/mux

## Getting Started

1. **Read the Architecture**: Understand how components interact
2. **Set up Environment**: Follow the Build Guide
3. **Run Locally**: Start with local development setup
4. **Explore Code**: Use AGENTS.md for code navigation

## Contributing

When making changes:

1. Update relevant documentation
2. Follow existing code patterns
3. Test on multiple platforms
4. Update AGENTS.md if architecture changes

## Support

For issues not covered in [Troubleshooting](TROUBLESHOOTING.md):

1. Check the logs (see Troubleshooting → Debug Logging)
2. Review the relevant protocol documentation
3. Create an issue with detailed information
