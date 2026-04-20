<p align="center">
  <img src="assets/social-preview.png" alt="SnapBack" width="700">
</p>

<p align="center">
  <strong>Attention manager for Claude Code</strong><br>
  Pauses your media, focuses your IDE, snaps you back when done.
</p>

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#cli">CLI</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-black?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/claude-hooks-D97757?style=flat-square" alt="Claude Hooks">
</p>

---

## The Problem

You're watching YouTube while Claude Code works. Claude finishes and asks a question, but you're not paying attention. Minutes pass. Productivity lost.

## The Solution

**SnapBack** hooks into Claude Code and:

1. **Pauses** your browser media (YouTube, etc.)
2. **Plays** a notification sound
3. **Focuses** your IDE and terminal
4. **Returns** you to your video when you respond

No more missed prompts. No more context switching friction.

---

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/teoobarca/snapback/main/get.sh | bash
```

The installer will:
- Download SnapBack to `~/.snapback/`
- Add the `snapback` command to your PATH
- Walk you through configuration (focus apps, browser, etc.)
- Set up Claude Code hooks automatically
- Build the optional menu-bar app (if Swift is available)

<details>
<summary>Manual installation</summary>

```bash
git clone https://github.com/teoobarca/snapback.git ~/.snapback
cd ~/.snapback
./snapback install
```

</details>

<details>
<summary>Non-interactive install (CI / dotfiles)</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/teoobarca/snapback/main/get.sh | bash
snapback install -y   # accepts defaults: Cursor + Ghostty, Chrome, full mode
```

</details>

---

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│  YouTube ▶️     │ ──▶ │  IDE (focused)  │ ──▶ │  YouTube ▶️     │
│  (paused)       │     │                 │     │  (resumed)      │
│                 │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
   Claude asks            You respond            Back to video
```

SnapBack registers four [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks):

| Hook | Fires when | SnapBack action |
|------|-----------|-----------------|
| `PermissionRequest` | Claude asks for permission | Pause media, focus IDE |
| `Stop` | Claude finishes a turn | Pause media, focus IDE |
| `PostToolUse` | A tool completes successfully | Resume media, return to previous app |
| `UserPromptSubmit` | You send a message | Resume media, return to previous app |

---

## CLI

```
snapback install [-y]        # Install and configure (or reconfigure)
snapback status              # Show config, hooks, permissions, menu-bar app
snapback on | off            # Enable / disable hooks (keeps config)
snapback mode [full|sound|switch]  # full = sound + focus, sound = sound only, switch = focus only
snapback volume [0.0-1.0]   # Get or set notification volume
snapback browser [NAME]      # Get or set browser (Chrome, Arc, Brave, Edge, Firefox)
snapback focus list|add|remove|set  # Manage focus apps
snapback config show|get|set|path   # Read or write config values
snapback test                # Play a notification preview
snapback app                 # Launch the menu-bar app
snapback update              # Pull latest version and rebuild menu-bar app
snapback uninstall           # Remove everything (config, hooks, app, symlinks)
```

### Menu-bar app

An optional SwiftUI menu-bar app lets you toggle SnapBack, change mode/volume,
and manage focus apps without opening a terminal. Built locally during
`snapback install` (requires Xcode Command Line Tools, macOS 13+). Launch with
`snapback app` or from `/Applications/SnapBack.app`.

---

## Configuration

Config file: `~/.config/snapback/config`

| Option | Default | Description |
|--------|---------|-------------|
| `FOCUS_APPS` | `("Cursor" "Ghostty")` | Apps to focus, in order (last stays on top) |
| `FOCUS_DELAY` | `0.5` | Seconds between focusing each app |
| `BROWSER` | `"Google Chrome"` | Browser for media control |
| `SEEK_BACK_SECONDS` | `1` | Rewind amount when resuming video |
| `THROTTLE_SECONDS` | `2` | Cooldown between triggers |
| `NOTIFICATION_SOUND` | `"default"` | `"default"`, path to `.mp3`, or `""` to disable |
| `VOLUME` | `"1.0"` | Notification volume (`0.0` – `1.0`) |
| `MODE` | `"full"` | `"full"`, `"sound"`, or `"switch"` |

All options can be changed via `snapback config set KEY VALUE` or the menu-bar app.

---

## Requirements

- **macOS 12+** (uses AppleScript for window and media automation)
- **Chromium-based browser** — Chrome, Arc, Brave, Edge (Safari support planned)
- **Claude Code** with hooks support
- `jq` — for automatic hook installation (bundled with Homebrew, etc.)

---

## Known Limitations

> These are Claude Code hook constraints, not SnapBack bugs.

- **No decline hook** — declining a permission request doesn't fire a hook, so SnapBack can't detect it. You'll switch back manually.
- **Failed tools don't trigger** — `PostToolUse` only fires on successful tool execution.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Media doesn't pause | Run `./snapback.sh` manually once to trigger macOS permission dialogs |
| Permission errors | System Settings → Privacy & Security → Automation → enable for your terminal |
| Apps not focusing | Increase `FOCUS_DELAY` to `0.7` or `1.0` |
| Too many notifications | Increase `THROTTLE_SECONDS` |
| Wrong app name | Check names with: `osascript -e 'tell app "System Events" to get name of every process'` |
| General diagnosis | Run `snapback status` for a full health check |

<details>
<summary>Manual hook setup (if you skipped the installer)</summary>

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.snapback/snapback.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "~/.snapback/snapback.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write|Bash", "hooks": [{ "type": "command", "command": "~/.snapback/snapback-resume.sh" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "~/.snapback/snapback-resume.sh" }] }
    ]
  }
}
```

</details>

---

## Mobile companion (experimental)

v1.3.0 ships a desktop bridge daemon inside the menu-bar app that will talk to
a future Android companion to lock your phone screen when Claude blocks on you.
The bridge is feature-complete against the [wire protocol](docs/PROTOCOL.md)
and can be tested with the included protocol test vectors.

```bash
snapback mobile enable      # start the bridge daemon
snapback mobile status      # check if the socket is live
snapback mobile pair        # pair with the Android app (when available)
```

The Android app is in development. See `docs/PROTOCOL.md` for the full spec.

---

## License

MIT © [teoobarca](https://github.com/teoobarca)
