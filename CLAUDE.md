# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make build    # Compile AppleScript sources to .app bundles in build/
make install  # Build and install to ~/Applications/
make clean    # Remove build directory
```

After installation, both apps must be opened manually once to grant macOS automation permissions (macOS displays permission dialogs on first run).

## Architecture

This is a macOS automation utility written in AppleScript, designed to work with Claude Code hooks.

**Two companion apps:**
- **AIAttention.app** (`src/AIAttention.applescript`) - Triggered on Claude Code permission requests:
  - Saves the current frontmost app to `/tmp/ai_attention_return_app`
  - Saves Chrome's playing state to `/tmp/ai_attention_chrome_state`
  - Pauses video/audio in Chrome's active tab via JavaScript injection
  - Plays a notification sound (embedded `notification.mp3`)
  - Focuses Cursor, then Ghostty (so terminal ends up on top)
  - 2-second throttle via `/var/folders/.../ai_attention_last`

- **AIResume.app** (`src/AIResume.applescript`) - Restores previous state:
  - Reads and deletes `/tmp/ai_attention_return_app`
  - If returning to Chrome and it was playing, resumes media
  - Otherwise activates the saved app
  - Has its own 2-second throttle

**Helper script:**
- `launch-attention.sh` - Alternative launcher that captures frontmost app before running AIAttention

**State files (temporary):**
- `/tmp/ai_attention_return_app` - App name to return to
- `/tmp/ai_attention_chrome_state` - Whether Chrome was playing ("true"/"false")
- `$TMPDIR/ai_attention_last` - Timestamp for AIAttention throttle
- `$TMPDIR/ai_resume_last` - Timestamp for AIResume throttle

## Claude Code Integration

Add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "open -g -a \"$HOME/Applications/AIAttention.app\""
          }
        ]
      }
    ]
  }
}
```
