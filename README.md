# AI Attention

A macOS utility that automatically manages your attention when Claude Code needs input.
It pauses media in Google Chrome and brings your development tools (Ghostty + Cursor) to the foreground.

## Features

- **Media Control**: Pauses video/audio in all Google Chrome tabs (YouTube, etc.).
- **Smart Exceptions**: Ignores Spotify web player tabs.
- **Window Management**: Focuses Cursor IDE first, then Ghostty terminal (keeping terminal on top).
- **Throttling**: Prevents multiple executions within 2 seconds (useful for repeated hooks).
- **Permissions**: Runs as a compiled `.app` to maintain stable macOS automation permissions.

## Installation

1.  Clone this repository.
2.  Run `make install`.
3.  **Critical Step**: Open `~/Applications/AIAttention.app` manually for the first time.
    - macOS will ask for permissions to control Google Chrome, System Events, etc.
    - Grant all requested permissions.
    - You may need to run it twice if the first run only triggers the prompt.

## Usage with Claude Code

Add the following to your `~/.claude/settings.json` to trigger AI Attention on permission requests:

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

## Development

- Source code is in `src/AIAttention.applescript`.
- To build locally without installing: `make build`.
- The compiled app will be in `build/AIAttention.app`.

## Troubleshooting

- **Error -2741 (syntax error)**: Usually means the app doesn't have permission to talk to Chrome.
    - Go to `System Settings` -> `Privacy & Security` -> `Automation`.
    - Ensure `AIAttention` has checkmarks for "Google Chrome" and "System Events".
- **App doesn't pause video**: Ensure the tab isn't frozen/sleeping. The script injects JavaScript to pause `<video>` and `<audio>` elements.


