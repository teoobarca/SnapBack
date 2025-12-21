# SnapBack

A macOS utility that automatically manages your attention when Claude Code needs input.
It pauses media in your browser and brings your development tools to the foreground, then "snaps" you back to where you were when you're done.

## Features

- **Media Control**: Pauses video/audio in browser active tabs (YouTube, etc.)
- **Window Management**: Focuses your IDE and terminal (keeping terminal on top)
- **Snap-Back**: Returns to previous app and resumes media when you submit a prompt
- **Seek Back**: Rewinds video slightly when resuming so you don't miss anything
- **Throttling**: Prevents multiple executions within configurable time window
- **Customizable**: Configure focus apps, browser, delays, sounds, and more

## Quick Install

```bash
git clone https://github.com/teoobarca/snapback.git
cd snapback
chmod +x install.sh
./install.sh
```

The installer will:
1. Ask you to configure your preferences
2. Save config to `~/.config/snapback/config`
3. Optionally add hooks to Claude Code settings
4. Trigger permission dialogs for macOS automation

## Manual Installation

1. Clone this repository
2. Copy `config.example` to `~/.config/snapback/config` and customize
3. Add the hooks to your `~/.claude/settings.json` (see below)
4. Run `snapback.sh` manually once to grant macOS automation permissions

## Configuration

Edit `~/.config/snapback/config`:

```bash
# Apps to focus when Claude needs attention (in order)
FOCUS_APPS=("Cursor" "Ghostty")

# Delay between focusing apps (seconds)
FOCUS_DELAY=0.5

# Browser to control (pause/resume media)
BROWSER="Google Chrome"

# Seconds to seek back when resuming video
SEEK_BACK_SECONDS=1

# Throttle time (seconds) - prevent rapid repeated triggers
THROTTLE_SECONDS=2

# Notification sound: "default", path to .mp3, or empty to disable
NOTIFICATION_SOUND="default"
```

## Claude Code Hooks

If you didn't use the installer, add this to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/snapback/snapback.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/snapback/snapback.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/snapback/snapback-resume.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/snapback/snapback-resume.sh"
          }
        ]
      }
    ]
  }
}
```

Replace `/path/to/snapback/` with the actual path to your clone.

## Files

- `snapback.sh` - Triggered on attention needed: saves current app, pauses browser, plays notification, focuses your apps
- `snapback-resume.sh` - Triggered after tool use: returns to previous app, seeks back and resumes media
- `install.sh` - Interactive installer
- `config.example` - Example configuration file
- `notification.mp3` - Default notification sound

## How It Works

1. **Claude needs attention** → `snapback.sh` runs:
   - Plays notification sound
   - Saves which app you were in
   - Checks if browser is playing media, saves state
   - Pauses browser media
   - Focuses your IDE, then terminal

2. **You submit a prompt** → `snapback-resume.sh` runs:
   - Returns you to the app you were in
   - If browser was playing, seeks back slightly and resumes

## Known Limitations

### Claude Code Hooks

SnapBack relies on Claude Code's hook system, which has some limitations:

- **No hook for user confirmation/decline**: There is no hook that fires when the user responds to a permission request (Accept, Decline, etc.). The `PostToolUse` hook only fires when a tool executes **successfully**.

- **Decline doesn't trigger resume**: If Claude requests to write a file, SnapBack brings you to your IDE. But if you **decline** and type a new prompt instead, the resume script won't automatically return you to your previous app. You'll need to switch back manually.

- **Only successful tool use triggers resume**: If a tool fails (e.g., permission denied, file not found), the `PostToolUse` hook doesn't fire, so resume won't trigger.

This is a limitation of Claude Code's hook API, not SnapBack itself. If Claude Code adds a `PermissionResponse` or `UserInput` hook in the future, SnapBack can be updated to handle these cases.

## Troubleshooting

- **Script doesn't pause video**: Run `snapback.sh` manually once and grant automation permissions in the macOS dialog.
- **Permission errors**: Check System Settings → Privacy & Security → Automation and ensure your terminal has access to your browser and System Events.
- **Apps not focusing properly**: Increase `FOCUS_DELAY` in config (try 0.7 or 1.0).
- **Too many notifications**: Increase `THROTTLE_SECONDS` in config.

## Requirements

- macOS (uses osascript/AppleScript for automation)
- Google Chrome, Arc, or other Chromium-based browser
- jq (optional, for automatic Claude Code hook installation)

## License

MIT
