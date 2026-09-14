# Vibe Terminal

A fast, cross-platform SSH terminal app for Linux, Windows, and macOS.

[한국어](README.ko.md)

## Features

- **Full terminal emulation** — xterm-compatible rendering with ANSI color support and zoom in/out for text size.
- **Host & session management** — organize connections into session groups, reconnect with one click, and keep multiple sessions open side by side.
- **SSH jump hosts & Kubernetes** — connect through bastion/jump hosts and open SSH sessions into Kubernetes pods.
- **Local terminal** — open a local shell alongside your SSH sessions in the same window.
- **Snippets panel** — save and reuse frequently used commands.
- **AI Chat panel** — a side panel for AI-assisted chat while you work.
- **Memo panel** — quick notes next to your terminal sessions.
- **Community panel** — discover and share resources with other users.
- **CLI tool integration** — automatically surfaces settings for Claude Code, Codex, and OpenCode when they're installed on your system.
- **Secure credential storage** — host credentials are stored using OS-level secure storage.
- **Image paste support** — paste images directly into supported transports.
- **Adaptive edge panels** — collapsible side drawers keep the interface uncluttered on both desktop and narrow windows.

## Getting started

```sh
flutter pub get
flutter analyze
```

### Build

```sh
# Linux
flutter build linux --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release
```

Prebuilt binaries for each platform are published on the [Releases](../../releases) page.

## License

This project is distributed under a source-available license — see [LICENSE](LICENSE). Third-party licenses for bundled terminal runtime dependencies are in `vendor/*/LICENSE`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please report security issues privately — see [SECURITY.md](SECURITY.md).
