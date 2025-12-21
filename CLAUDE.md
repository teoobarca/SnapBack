# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture

Two bash scripts that use inline AppleScript (osascript) for macOS automation, with configuration via `~/.config/snapback/config`.

### snapback.sh

Triggered on `PermissionRequest` and `Stop` hooks:

1. Loads config from `~/.config/snapback/config` (falls back to defaults)
2. Checks throttle - exits if called within `THROTTLE_SECONDS`
3. Gets frontmost app via osascript
4. If already in last focus app, just plays sound and exits
5. Plays notification sound async (`afplay`)
6. Runs single osascript that:
   - Checks if browser has playing media
   - Pauses media via JavaScript injection
   - Saves state to `/tmp/snapback_state` (format: `AppName:true/false`)
   - Focuses each app in `FOCUS_APPS` array with delay between

### snapback-resume.sh

Triggered on `PostToolUse` (Edit|Write|Bash) and `UserPromptSubmit` hooks:

1. Loads config from `~/.config/snapback/config`
2. Checks throttle - exits if called within `THROTTLE_SECONDS`
3. Resets attention throttle file (allows attention to fire again)
4. Reads and deletes `/tmp/snapback_state`
5. Parses state: app name and browser playing status
6. If returning to browser and it was playing:
   - Activates browser
   - Seeks back `SEEK_BACK_SECONDS` and resumes media
7. Otherwise just activates the saved app

## Configuration

Config file: `~/.config/snapback/config`

```bash
FOCUS_APPS=("Cursor" "Ghostty")  # Apps to focus, in order
FOCUS_DELAY=0.5                   # Delay between focusing apps
BROWSER="Google Chrome"           # Browser to control
SEEK_BACK_SECONDS=1              # Seconds to rewind when resuming
THROTTLE_SECONDS=2               # Prevent rapid triggers
NOTIFICATION_SOUND="default"     # "default", path to .mp3, or empty
```

## State Files

- `/tmp/snapback_state` - Combined state: `AppName:true` or `AppName:false`
- `$TMPDIR/snapback_last` - Timestamp for attention throttle
- `$TMPDIR/snapback_resume_last` - Timestamp for resume throttle

## Key Implementation Details

- **Dynamic AppleScript generation**: Focus script is built from `FOCUS_APPS` array at runtime
- **Single osascript call**: All browser interaction + state saving + focusing in one call for efficiency
- **Cross-throttle reset**: Each script resets the other's throttle file to allow proper alternation
- **State format**: `AppName:true/false` parsed with bash parameter expansion (`${state%:*}` and `${state##*:}`)

## Files

- `snapback.sh` - Main attention script
- `snapback-resume.sh` - Resume/return script
- `install.sh` - Interactive installer (creates config, adds Claude hooks)
- `config.example` - Example configuration
- `notification.mp3` - Default notification sound
- `RESEARCH.md` - Market research and competitor analysis
