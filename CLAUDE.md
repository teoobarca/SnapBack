# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

SnapBack is an attention manager for Claude Code. It pauses browser media, plays a notification sound, and focuses your IDE when Claude needs input. When you respond, it returns you to your previous app and resumes media.

## Architecture

```
get.sh              → Remote installer (curl | bash), downloads repo, adds to PATH, runs install
snapback            → CLI wrapper (install/status/on/off/mode/volume/browser/focus/config/test/app/update/uninstall)
install.sh          → Interactive configuration, sets up Claude hooks, optionally builds menu-bar app
snapback-lib.sh     → Shared config API (config_get/config_set with file locking), sourced by CLI and installer
snapback.sh         → Main attention script (triggered by Claude hooks)
snapback-resume.sh  → Resume script (returns to previous app)
SnapBackApp/        → Native macOS menu-bar app (Swift, built via build-app.sh)
```

### Core Scripts

**snapback.sh** - Triggered on `PermissionRequest` and `Stop` hooks:
1. Load config; resolve notification sound path
2. **Sound-only fast path**: if `MODE=sound`, play sound and exit immediately (no throttle, no app detection)
3. Throttle check (skip if called within `THROTTLE_SECONDS`)
4. Get frontmost app; if already in last focus app → just play sound and exit
5. If `FOCUS_APPS` is empty → just play sound and exit
6. Play sound async, pause browser media if playing
7. Save state to `/tmp/snapback_state` (format: `AppName:true/false`)
8. Focus each app in `FOCUS_APPS` array with `FOCUS_DELAY` between them

**snapback-resume.sh** - Triggered on `PostToolUse` (matcher: `Edit|Write|Bash`) and `UserPromptSubmit`:
1. Throttle check, reset attention throttle
2. Read and delete `/tmp/snapback_state`
3. If returning to browser and media was playing → seek back and resume
4. Otherwise just activate the saved app

**snapback-lib.sh** - Shared config library sourced by `snapback` CLI and `install.sh`:
- `config_get KEY` — reads a key from the config file (handles both scalars and arrays)
- `config_set KEY VALUE [--allow-new]` — writes a key with file locking (lockdir pattern)
- Known keys table with type tags (scalar/array) for validation
- Bash 3.2-safe escape and rewrite helpers

### CLI Commands

The `snapback` CLI (v1.2.0) supports:

| Command | Description |
|---------|-------------|
| `install [-y]` | Interactive setup (delegates to `install.sh`) |
| `status` | Check config, hooks, permissions, menu-bar app, effective volume |
| `on` / `enable` | Enable Claude Code hooks (adds to `~/.claude/settings.json`) |
| `off` / `disable` | Disable Claude Code hooks (removes from settings, keeps config) |
| `mode [full\|sound]` | Get/set mode: `full` (sound + focus) or `sound` (sound only) |
| `volume [0.0-1.0]` | Get/set notification volume |
| `browser [NAME]` | Get/set browser for media control |
| `focus <sub>` | `list`, `add NAME`, `remove NAME`, `set NAME1 NAME2 ...` |
| `config <sub>` | `get KEY`, `set KEY VAL [--allow-new]`, `show [--json]`, `path` |
| `test` | Play a notification preview at effective volume |
| `app` | Launch the menu-bar app |
| `update` | Update to latest version (git pull or tarball); rebuilds menu-bar app if installed |
| `uninstall` / `remove` | Remove config, hooks, symlinks, menu-bar app |

### Configuration

Config file: `~/.config/snapback/config`

```bash
FOCUS_APPS=("Cursor" "Ghostty")  # Apps to focus, in order (last stays on top)
FOCUS_DELAY=0.5                   # Delay between focusing apps
BROWSER="Google Chrome"           # Browser for media control
SEEK_BACK_SECONDS=1              # Rewind when resuming video
THROTTLE_SECONDS=2               # Prevent rapid triggers
NOTIFICATION_SOUND="default"     # "default", path to .mp3, or "" to disable
VOLUME="1.0"                     # Notification volume (0.0 - 1.0), scaled by system volume
MODE="full"                      # "full" (sound + focus apps) or "sound" (sound only)
```

### State Files

- `/tmp/snapback_state` - Saved app and browser playing state
- `$TMPDIR/snapback_last` - Throttle timestamp for attention
- `$TMPDIR/snapback_resume_last` - Throttle timestamp for resume

### Menu-Bar App

`SnapBackApp/` contains a native Swift menubar app (LSUIElement, no dock icon):
- `Package.swift` — Swift package manifest
- `Sources/` — Swift source code
- `build-app.sh` — Builds via `swift build -c release`, creates `.app` bundle with Info.plist
- Installed to `/Applications/SnapBack.app`; launched via `snapback app`

### Claude Code Hooks

Hooks are written to `~/.claude/settings.json` via `jq`:
- **PermissionRequest** (matcher: `*`) → `snapback.sh`
- **Stop** → `snapback.sh`
- **PostToolUse** (matcher: `Edit|Write|Bash`) → `snapback-resume.sh`
- **UserPromptSubmit** → `snapback-resume.sh`

Hooks are additive — existing non-snapback hooks are preserved.

## Development Guide

### Making Changes

1. **Test locally first** - Run scripts directly before committing
2. **macOS Bash is old** - Use Bash 3.2 compatible syntax:
   - No `${var,,}` for lowercase → use `tr '[:upper:]' '[:lower:]'`
   - No associative arrays
   - No `|&` for pipe stderr → use `2>&1 |`
   - No `mapfile` / `readarray` → use `while IFS= read -r` loops
3. **AppleScript quirks** - App names from System Events may differ from display names (e.g., `ghostty` vs `Ghostty`)

### Version Updates

When releasing a new version:
1. Update `VERSION` in `snapback` (line 5)
2. Update `CFBundleVersion` and `CFBundleShortVersionString` in `SnapBackApp/build-app.sh`
3. Test the full flow: `get.sh` → `snapback install` → hooks working
4. Commit and push to main

### File Structure

```
snapback              # CLI tool - all user-facing commands
snapback.sh           # Attention script - pause media, play sound, focus IDE
snapback-resume.sh    # Resume script - return to previous app, resume media
snapback-lib.sh       # Shared config API (config_get/config_set)
install.sh            # Interactive installer
get.sh                # Remote installer for curl | bash
notification.mp3      # Default notification sound
config.example        # Example configuration (all 8 keys)
SnapBackApp/          # Native macOS menu-bar app (Swift)
  build-app.sh        #   Build script → creates SnapBack.app bundle
  Package.swift       #   Swift package manifest
  Sources/            #   Swift source code
tests/                # Test suite (bats)
  cli_typed.bats      #   CLI typed-config tests
  config_set.bats     #   config_set unit tests
docs/superpowers/     # Documentation (plans, specs)
assets/               # Social preview images, icons
README.md             # User documentation
CLAUDE.md             # This file
RESEARCH.md           # Market research
ROADMAP.md            # Future improvements
LICENSE               # License file
```

### Testing

```bash
# Test attention script directly
./snapback.sh

# Test resume script
echo "Google Chrome:true" > /tmp/snapback_state
./snapback-resume.sh

# Run bats tests (requires bats-core)
bats tests/

# Test full install flow
rm -rf ~/.snapback ~/.config/snapback
./get.sh
```

### Common Issues

- **Permission errors** - Run `snapback.sh` manually to trigger macOS permission dialogs
- **App not focusing** - Check exact app name with: `osascript -e 'tell application "System Events" to get name of every process'`
- **Case sensitivity** - AppleScript returns lowercase process names; comparisons use `tr` for case-insensitive matching

## Key Implementation Details

- **Single osascript call** - Browser check + pause + state save + focus in one call for efficiency
- **Cross-throttle reset** - Each script resets the other's throttle to allow proper alternation
- **Case-insensitive matching** - Uses `tr` because macOS Bash lacks `${var,,}`
- **TTY input for curl|bash** - `install.sh` reads from `/dev/tty` when stdin is piped
- **File-locking for config writes** - `config_set` uses a lockdir (`mkdir` atomic) with subshell + EXIT trap
- **Volume scaling** - Effective volume = `VOLUME` setting × system output volume
- **Sound-only fast path** - `MODE=sound` skips all app detection/throttle for minimal latency
