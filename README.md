# Vibe Terminal

A fast, cross-platform SSH terminal app for Linux, Windows, and macOS.

[한국어](README.ko.md)

## Features

- **Full terminal emulation** — xterm-compatible rendering with ANSI color support and zoom in/out for text size.
- **Host & session management** — organize connections into session groups, reconnect with one click, and keep multiple sessions open side by side.
- **Tab groups** — group sessions inside a workspace with a name and color, collapse groups, and drag sessions in or out, like vertical browser tabs.
- **Compact session list** — when the left panel is collapsed, sessions stay visible as icons with connection and agent status.
- **Session info on hover** — hover a session to see its connection type, address, jump host, operating system, and status.
- **SSH jump hosts** — reach SSH destinations through bastions. Previously saved Kubernetes relay hosts keep connecting.
- **Local terminal** — open a local shell alongside SSH sessions; the bundled helper keeps local sessions available across app restarts.
- **Snippets panel** — save and reuse frequently used commands.
- **AI Chat panel** — a side panel for AI-assisted chat while you work.
- **GUI document mode** — read terminal output as selectable text, copy code blocks, open web links, and write messages in a separate composer.
- **Agent Chat** — coordinate CLI agents running in your sessions from a side panel, including scheduled routines.
- **Agent autopilot** — optionally let supported CLI agents resume after interruptions or usage limits and approve low-risk prompts once.
- **Puppy ReCap** — with an AI connection configured, click the 🐶 button to get a three-line summary of what you have done in the session.
- **AI reply suggestions** — use your configured AI connection to request reply choices or suggest them when a supported agent is waiting. A reply is sent only when you select it.
- **Touch control** — optionally send taps and clicks to terminal programs that support mouse input; keep scrolling and long-press text selection available.
- **Gesture shortcuts** — customize double-tap and double-click actions, including Tab and key combinations, without changing the default selection behavior until configured.
- **Memo panel** — quick notes next to your terminal sessions.
- **Community panel** — discover and share resources with other users.
- **CLI tool integration** — automatically surfaces settings for Claude Code, Codex, and OpenCode when they're installed on your system.
- **Secure credential storage** — host credentials are stored using OS-level secure storage.
- **Image paste support** — paste images directly into supported transports.
- **Adaptive edge panels** — collapsible side drawers keep the interface uncluttered on both desktop and narrow windows.

## Getting started

Use Flutter **3.47.2**, the version pinned by CI and release builds.

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
