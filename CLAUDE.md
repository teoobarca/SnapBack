# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

SnapBack is an attention manager for Claude Code. It pauses browser media, plays a notification sound, and focuses your IDE when Claude needs input. When you respond, it returns you to your previous app and resumes media.

## Architecture

```
get.sh              → Downloads from GitHub, adds to PATH, runs install
snapback            → CLI wrapper (install/status/on/off/update/uninstall)
install.sh          → Interactive configuration, sets up Claude hooks
snapback.sh         → Main attention script (triggered by Claude hooks)
snapback-resume.sh  → Resume script (returns to previous app)
```

### Core Scripts

**snapback.sh** - Triggered on `PermissionRequest` and `Stop` hooks:
1. Throttle check (skip if called within `THROTTLE_SECONDS`)
2. Check if already in last focus app → just play sound and exit
3. Get frontmost app, pause browser media if playing
4. Save state to `/tmp/snapback_state` (format: `AppName:true/false`)
5. Focus each app in `FOCUS_APPS` array

**snapback-resume.sh** - Triggered on `PostToolUse` and `UserPromptSubmit`:
1. Read and delete `/tmp/snapback_state`
2. If returning to browser and media was playing → seek back and resume
3. Otherwise just activate the saved app

### Configuration

Config file: `~/.config/snapback/config`

```bash
FOCUS_APPS=("Cursor" "Ghostty")  # Apps to focus, in order (last stays on top)
FOCUS_DELAY=0.5                   # Delay between focusing apps
BROWSER="Google Chrome"           # Browser for media control
SEEK_BACK_SECONDS=1              # Rewind when resuming video
THROTTLE_SECONDS=2               # Prevent rapid triggers
NOTIFICATION_SOUND="default"     # "default", path to .mp3, or "" to disable
```

### State Files

- `/tmp/snapback_state` - Saved app and browser playing state
- `$TMPDIR/snapback_last` - Throttle timestamp for attention
- `$TMPDIR/snapback_resume_last` - Throttle timestamp for resume

## Development Guide

### Making Changes

1. **Test locally first** - Run scripts directly before committing
2. **macOS Bash is old** - Use Bash 3.2 compatible syntax:
   - No `${var,,}` for lowercase → use `tr '[:upper:]' '[:lower:]'`
   - No associative arrays
   - No `|&` for pipe stderr → use `2>&1 |`
3. **AppleScript quirks** - App names from System Events may differ from display names (e.g., `ghostty` vs `Ghostty`)

### Version Updates

When releasing a new version:
1. Update `VERSION` in `snapback` (line 5)
2. Test the full flow: `get.sh` → `snapback install` → hooks working
3. Commit and push to main

### File Structure

```
snapback            # CLI tool - commands: install, status, on, off, update, uninstall
snapback.sh         # Attention script - pause media, focus IDE
snapback-resume.sh  # Resume script - return to previous app
install.sh          # Interactive installer
get.sh              # Remote installer for curl | bash
notification.mp3    # Default notification sound
config.example      # Example configuration
README.md           # User documentation
CLAUDE.md           # This file
RESEARCH.md         # Market research
ROADMAP.md          # Future improvements
```

### Testing

```bash
# Test attention script directly
./snapback.sh

# Test resume script
echo "Google Chrome:true" > /tmp/snapback_state
./snapback-resume.sh

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
