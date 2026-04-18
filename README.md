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
- Add `snapback` command to your PATH
- Guide you through configuration

<details>
<summary>Alternative: Manual installation</summary>

```bash
git clone https://github.com/teoobarca/snapback.git
cd snapback
./snapback install
```

</details>

---

## CLI Usage

```bash
snapback install [-y]        # Interactive installation and configuration
snapback status              # Check configuration and menu-bar state
snapback on                  # Enable hooks for selected providers
snapback off                 # Disable hooks for selected providers
snapback hooks list          # List available hook providers
snapback hooks get           # Show selected providers
snapback hooks set all       # Set providers: all | none | claude opencode
snapback hooks add opencode  # Add provider(s) to current selection
snapback hooks remove claude # Remove provider(s) from current selection
snapback hooks status        # Show per-provider hook status
snapback mode [MODE]         # Get/set mode: both | switches | sound
snapback volume [VAL]        # Get/set notification volume (0.0 - 1.0)
snapback browser [NAME]      # Get/set browser (Google Chrome, Arc, Safari, Firefox, Brave)
snapback focus list          # List focus apps
snapback focus add NAME      # Add an app to focus list
snapback focus remove NAME   # Remove an app from focus list
snapback focus set N1 N2 ... # Replace the entire focus list
snapback config get KEY      # Get a config value
snapback config set KEY VAL  # Set a config value
snapback config show         # Show all config values
snapback config path         # Print config file path
snapback test                # Play a notification preview
snapback app                 # Launch the menu-bar app (if installed)
snapback app install         # Build + install + launch menu-bar app
snapback update              # Update to latest version (and rebuild menu-bar app if installed)
snapback uninstall           # Remove config, hooks, and menu-bar app
```

### Menu-bar app (optional)

SnapBack ships with an optional SwiftUI menu-bar app that lets you tweak
volume, mode, focus apps, and the SnapBack on/off switch without a
terminal. It's built locally from source during `snapback install`
(requires Xcode Command Line Tools / Swift 5.9+, macOS 13+). Open with
`snapback app` or from `/Applications/SnapBack.app`.

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

**Triggers:**
- `PermissionRequest` / `Stop` → Pauses media, focuses IDE
- `PostToolUse` / `UserPromptSubmit` → Returns to previous app, resumes media

---

## Configuration

Config file: `~/.config/snapback/config`

| Option | Default | Description |
|--------|---------|-------------|
| `FOCUS_APPS` | `("Cursor" "Ghostty")` | Apps to focus (in order, last stays on top) |
| `FOCUS_DELAY` | `0.5` | Seconds between focusing each app |
| `BROWSER` | `"Google Chrome"` | Browser for media control |
| `SEEK_BACK_SECONDS` | `1` | Rewind when resuming video |
| `THROTTLE_SECONDS` | `2` | Cooldown between triggers |
| `NOTIFICATION_SOUND` | `"default"` | Sound file, `"default"`, or `""` to disable |
| `HOOK_PROVIDERS` | `("claude")` | Hook targets: `claude`, `opencode`, both, or `()` |

---

## Hook Providers

SnapBack can integrate with one, many, or no coding agents at all.

- `snapback hooks set claude` → Claude Code only
- `snapback hooks set opencode` → OpenCode only
- `snapback hooks set all` → Claude + OpenCode
- `snapback hooks set none` → disable hook wiring
- `snapback hooks add opencode` → add OpenCode while keeping current providers
- `snapback hooks remove claude` → remove Claude from current providers

### Claude Code hooks

<details>
<summary>Manual configuration (if you skipped installer + CLI)</summary>

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/snapback.sh"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "/path/to/snapback.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "Edit|Write|Bash", "hooks": [{"type": "command", "command": "/path/to/snapback-resume.sh"}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "/path/to/snapback-resume.sh"}]}
    ]
  }
}
```

</details>

### OpenCode hooks

SnapBack installs a managed plugin at `~/.config/opencode/plugins/snapback.js`.
This plugin triggers:

- `snapback.sh` on `permission.asked` and `session.idle`
- `snapback-resume.sh` on `tool.execute.after` and `command.executed`

---

## Known Limitations

> **Note:** These are Claude Code hook limitations, not SnapBack bugs.

- **No decline hook** — If you decline a permission request, SnapBack can't detect it. You'll need to switch back manually.
- **Failed tools don't trigger** — `PostToolUse` only fires on successful tool execution.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Video doesn't pause | Run `./snapback.sh` manually to trigger permission dialogs |
| Permission errors | System Settings → Privacy & Security → Automation |
| Apps not focusing | Increase `FOCUS_DELAY` to `0.7` or `1.0` |
| Too many notifications | Increase `THROTTLE_SECONDS` |
| Check current status | Run `snapback status` |

---

## Requirements

- macOS (uses AppleScript for automation)
- Chromium-based browser (Chrome, Arc, Brave, Edge)
- `jq` (optional, for automatic hook installation)

---

## License

MIT © [teoobarca](https://github.com/teoobarca)
