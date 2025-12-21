# SnapBack Roadmap

Future improvements and feature ideas. Not currently planned for implementation.

## CLI Tool

Convert SnapBack into a proper CLI tool with subcommands:

```bash
snapback install     # Interactive installation
snapback configure   # Reconfigure settings
snapback status      # Check if everything works
snapback on/off      # Enable/disable hooks
snapback uninstall   # Remove config and hooks
```

### Implementation Options

**Phase 1: Bash CLI wrapper**
- Single `snapback` script with subcommands
- Symlink to `/usr/local/bin/snapback`
- Minimal effort, works immediately

**Phase 2: Homebrew distribution**
- Create homebrew tap repository
- Write formula file
- Enable `brew install snapback`

## Feature Ideas

### High Priority
- Uninstall script
- Status/test command
- Safari browser support (different AppleScript syntax)
- Arc browser support

### Medium Priority
- Quiet hours (e.g., no notifications 22:00-08:00)
- Different sounds for different events
- Multi-tab media pause (all tabs, not just active)
- Debug logging

### Nice to Have
- macOS menubar app with on/off toggle
- Spotify/Apple Music pause support
- macOS Focus modes integration
- Config validation (check if FOCUS_APPS exist)
