#!/bin/bash
# SnapBack - pauses browser media, plays sound, focuses your IDE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/snapback/config"

# Defaults
FOCUS_APPS=("Cursor" "Ghostty")
FOCUS_DELAY=0.5
BROWSER="Google Chrome"
THROTTLE_SECONDS=2
NOTIFICATION_SOUND="default"
MODE="full"
VOLUME="1.0"

# Load user config if exists
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

# Resolve notification sound path
if [[ "$NOTIFICATION_SOUND" == "default" ]]; then
  NOTIFICATION_SOUND="$SCRIPT_DIR/notification.mp3"
elif [[ -z "$NOTIFICATION_SOUND" ]]; then
  NOTIFICATION_SOUND=""
fi

# Play the configured notification sound at the effective volume.
# Silent no-op if NOTIFICATION_SOUND is empty or missing.
_play_notification() {
  [[ -n "$NOTIFICATION_SOUND" && -f "$NOTIFICATION_SOUND" ]] || return 0
  local sysVol effectiveVol
  sysVol=$(osascript -e "output volume of (get volume settings)" 2>/dev/null || echo 100)
  effectiveVol=$(echo "$VOLUME * $sysVol / 100" | bc -l 2>/dev/null || echo "$VOLUME")
  afplay -v "$effectiveVol" "$NOTIFICATION_SOUND" &
}

# Bridge integration (1.3.0+): silently poke the mobile bridge daemon.
# Runs unconditionally so both MODE=full and MODE=sound notify the phone.
# Source snapback-lib.sh for the shared snapback_bridge_poke helper; if the
# library isn't present the bridge feature is simply off and the hook continues.
if [[ -f "$SCRIPT_DIR/snapback-lib.sh" ]]; then
  # shellcheck source=snapback-lib.sh
  source "$SCRIPT_DIR/snapback-lib.sh"
elif [[ -f "/usr/local/share/snapback/snapback-lib.sh" ]]; then
  # shellcheck disable=SC1091
  source "/usr/local/share/snapback/snapback-lib.sh"
fi
command -v snapback_bridge_poke >/dev/null 2>&1 && \
  snapback_bridge_poke attention PermissionRequest

# FAST PATH: Sound-only mode - just play sound and exit immediately
# No throttling, no app detection, maximum speed
if [[ "$MODE" == "sound" ]]; then
  _play_notification
  exit 0
fi

# === FULL MODE BELOW ===

STATE_FILE="/tmp/snapback_state"
THROTTLE_FILE="${TMPDIR:-/tmp}/snapback_last"
RESUME_THROTTLE_FILE="${TMPDIR:-/tmp}/snapback_resume_last"

# Throttle: skip if called within throttle window
now=$(date +%s)
if [[ -f "$THROTTLE_FILE" ]]; then
  last=$(cat "$THROTTLE_FILE" 2>/dev/null || echo 0)
  if (( now - last <= THROTTLE_SECONDS )); then
    exit 0
  fi
fi
echo "$now" > "$THROTTLE_FILE"

# Reset resume throttle so resume can run after this
rm -f "$RESUME_THROTTLE_FILE" 2>/dev/null || true

# Get frontmost app
frontmost=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || true)
frontmostLower=$(echo "$frontmost" | tr '[:upper:]' '[:lower:]')

# If FOCUS_APPS is empty, just play sound and exit
if (( ${#FOCUS_APPS[@]} == 0 )); then
  _play_notification
  exit 0
fi

# If already in last focus app, just play sound and exit (case-insensitive comparison)
lastFocusApp="${FOCUS_APPS[${#FOCUS_APPS[@]}-1]}"
lastFocusAppLower=$(echo "$lastFocusApp" | tr '[:upper:]' '[:lower:]')
if [[ "$frontmostLower" == "$lastFocusAppLower" ]]; then
  _play_notification
  exit 0
fi

# Play sound immediately (async)
_play_notification

# Determine if we should save state (skip workflow apps)
saveState=""
skipApps=$(printf '%s|' "${FOCUS_APPS[@]}" | tr '[:upper:]' '[:lower:]' | sed 's/|$//')
if [[ -z "$frontmost" || "$frontmostLower" =~ ^($skipApps|snapback|applet)$ ]]; then
  rm -f "$STATE_FILE" 2>/dev/null || true
else
  saveState="$frontmost"
fi

# Build AppleScript for focus apps
focusScript=""
for i in "${!FOCUS_APPS[@]}"; do
  app="${FOCUS_APPS[$i]}"
  focusScript+="try
  tell application \"$app\" to activate
end try
"
  if (( i < ${#FOCUS_APPS[@]} - 1 )); then
    focusScript+="delay $FOCUS_DELAY
"
  fi
done

# Single osascript: check browser state, pause if playing, save state, focus apps
osascript <<EOF 2>/dev/null || true
set browserWasPlaying to false

-- Check and pause browser
if application "$BROWSER" is running then
  tell application "$BROWSER"
    try
      if (count of windows) > 0 then
        repeat with w in windows
          try
            set t to active tab of w
            set isPlaying to execute t javascript "(() => { return Array.from(document.querySelectorAll('video,audio')).some(m => !m.paused && !m.ended && m.readyState > 2); })();"
            if isPlaying is true or isPlaying is "true" then
              set browserWasPlaying to true
              execute t javascript "(() => { document.querySelectorAll('video,audio').forEach(m=>{try{m.pause()}catch(e){}}); })();"
              exit repeat
            end if
          end try
        end repeat
      end if
    end try
  end tell
end if

-- Save state to file (app:browserWasPlaying)
set returnApp to "$saveState"
if returnApp is not "" then
  if browserWasPlaying then
    do shell script "printf '%s' " & quoted form of (returnApp & ":true") & " > /tmp/snapback_state"
  else
    do shell script "printf '%s' " & quoted form of (returnApp & ":false") & " > /tmp/snapback_state"
  end if
end if

-- Focus apps
$focusScript
EOF
