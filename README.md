<p align="center">
  <img src="assets/social-preview.png" alt="SnapBack" width="700">
</p>

<p align="center">
  <strong>Attention manager for Claude Code</strong><br>
  Pauses your media, focuses your IDE, locks your phone, snaps you back when done.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#mobile-companion">Mobile</a> •
  <a href="#cli-reference">CLI</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-black?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/android-companion-3DDC84?style=flat-square" alt="Android">
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
4. **Locks your phone** if you're doomscrolling (optional, Android)
5. **Returns** you to your video when you respond

No more missed prompts. No more context switching friction.

---

## Quick Start

### Prerequisites

- **macOS 12+**
- **Claude Code** with [hooks support](https://docs.anthropic.com/en/docs/claude-code/hooks)
- **`jq`** — `brew install jq` (for automatic hook installation)
- **Chromium browser** — Chrome, Arc, Brave, or Edge

### Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/teoobarca/snapback/main/get.sh | bash
```

That's it. No prompts, no sudo, no passwords. The installer will:
1. Download SnapBack to `~/.snapback/`
2. Add the `snapback` command to your PATH (`~/.local/bin`)
3. Auto-detect your IDE, terminal, and browser
4. Set up Claude Code hooks automatically
5. Build the menu-bar app (if Xcode Command Line Tools are available)

**Restart Claude Code** after installing to activate hooks.

<details>
<summary>Manual / offline installation</summary>

```bash
git clone https://github.com/teoobarca/snapback.git ~/.snapback
cd ~/.snapback
./snapback install
```

</details>

<details>
<summary>Interactive install (choose your own apps)</summary>

```bash
snapback install -i   # guided setup with prompts
```

</details>

### Verify it works

```bash
snapback status   # full health check — hooks, permissions, config
snapback test     # play a notification sound preview
```

---

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│  YouTube        │ ──▶ │  IDE (focused)  │ ──▶ │  YouTube        │
│  (paused)       │     │                 │     │  (resumed)      │
│                 │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
   Claude asks            You respond            Back to video
```

SnapBack registers four [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks):

| Hook | Fires when | SnapBack action |
|------|-----------|-----------------|
| `PermissionRequest` | Claude asks for permission | Pause media, focus IDE, lock phone |
| `Stop` | Claude finishes a turn | Pause media, focus IDE, lock phone |
| `PostToolUse` | A tool completes successfully | Resume media, return to previous app |
| `UserPromptSubmit` | You send a message | Resume media, unlock phone |

---

## Mobile Companion

An Android companion app that **locks your phone screen** when Claude needs your attention, so you stop doomscrolling and get back to work.

### How it works

Your Mac and phone stay connected over your local WiFi. When Claude blocks on you, the Mac tells your phone to lock. When you respond to Claude, the phone unlocks. No cloud, no account, no internet required — just the same WiFi network.

### Setup

#### 1. Install the Android app

Download `snapback-mobile-1.4.0-release.apk` from [GitHub Releases](https://github.com/teoobarca/snapback/releases) and sideload it:

1. On your phone: **Settings > Security > Install unknown apps** — enable for your browser or file manager
2. Download and open the APK
3. The app will walk you through granting **Accessibility** permission (required to lock the screen)
4. Follow the OEM-specific battery optimization card (Samsung, Xiaomi, OnePlus, etc.) to prevent Android from killing the service

#### 2. Make sure the menu-bar app is running on your Mac

```bash
snapback app   # launches the menu-bar app (or open /Applications/SnapBack.app)
```

If you skipped the menu-bar app during install, build it now:

```bash
snapback update   # rebuilds and installs the menu-bar app
```

> Requires Xcode Command Line Tools: `xcode-select --install`

#### 3. Pair

1. Click the SnapBack icon in your Mac menu bar
2. Go to the **Mobile** tab
3. Click **Pair mobile...**  — a QR code appears
4. Open the SnapBack Mobile app on your phone and scan the QR code

The status dot turns green when connected. Done.

#### Requirements

- Mac and phone on the **same WiFi network**
- **Accessibility permission** enabled on Android (Settings > Accessibility > SnapBack Mobile)
- **Battery optimization disabled** for SnapBack Mobile (prevents Android from killing the background service)

#### Mobile troubleshooting

| Issue | Fix |
|-------|-----|
| Phone never locks | Enable Accessibility: Settings > Accessibility > SnapBack Mobile > Enable |
| Status stays yellow/red | Check both devices are on the same WiFi network |
| Keeps disconnecting | Disable battery optimization for SnapBack Mobile |
| Samsung/Xiaomi/OnePlus kills the service | Follow the OEM instructions shown in the app's Settings screen |
| Need to re-pair | On Mac: click **Unpair** in the Mobile tab, then **Pair mobile...** again |
| Check bridge logs | `snapback mobile logs` |

---

## CLI Reference

```
snapback install             # Auto-setup (no prompts, no sudo)
snapback install -i          # Interactive guided setup
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

# Mobile
snapback mobile pair         # Open menu-bar app to pair with phone
snapback mobile unpair       # Remove pairing
snapback mobile status       # Check bridge connection
snapback mobile enable       # Enable mobile bridge
snapback mobile disable      # Disable mobile bridge
snapback mobile logs         # Tail bridge log file
```

### Menu-bar app

An optional SwiftUI menu-bar app lets you toggle SnapBack, change mode/volume, manage focus apps, and pair your phone — all without opening a terminal. Built locally during `snapback install` (requires Xcode Command Line Tools, macOS 13+). Launch with `snapback app` or from `/Applications/SnapBack.app`.

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

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Media doesn't pause | Run `./snapback.sh` manually once to trigger macOS permission dialogs |
| Permission errors | System Settings > Privacy & Security > Automation > enable for your terminal |
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

## Known Limitations

> These are Claude Code hook constraints, not SnapBack bugs.

- **No decline hook** — declining a permission request doesn't fire a hook, so SnapBack can't detect it. You'll switch back manually.
- **Failed tools don't trigger** — `PostToolUse` only fires on successful tool execution.

---

## Building from source

### Desktop (macOS menu-bar app)

```bash
cd SnapBackApp
swift build          # debug build
swift test           # run tests
./build-app.sh       # produce SnapBack.app bundle
```

### Mobile (Android companion)

Requires JDK 17 and Android SDK (API 36).

```bash
cd SnapBackMobile
./gradlew :app:assembleDebug          # debug APK
./gradlew :app:testDebugUnitTest      # unit tests
```

See [SnapBackMobile/README.md](SnapBackMobile/README.md) for release signing and advanced testing.

---

## License

MIT © [teoobarca](https://github.com/teoobarca)
