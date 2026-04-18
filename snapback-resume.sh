#!/bin/bash
# SnapBack Resume - returns to previous app and resumes browser media
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/snapback/config"

# Defaults
BROWSER="Google Chrome"
SEEK_BACK_SECONDS=1
THROTTLE_SECONDS=2

# Load user config if exists. A syntax error inside `source` aborts this
# shell even with `|| ...`, so validate in a subshell first.
if [[ -f "$CONFIG_FILE" ]]; then
  if _CFG="$CONFIG_FILE" bash -c 'source "$_CFG"' >/dev/null 2>&1; then
    source "$CONFIG_FILE"
  else
    echo "snapback-resume: warning: $CONFIG_FILE has a syntax error, using defaults" >&2
  fi
fi

STATE_FILE="/tmp/snapback_state"
THROTTLE_FILE="${TMPDIR:-/tmp}/snapback_resume_last"
ATTENTION_THROTTLE_FILE="${TMPDIR:-/tmp}/snapback_last"

# Throttle: skip if called within throttle window
now=$(date +%s)
if [[ -f "$THROTTLE_FILE" ]]; then
  last=$(cat "$THROTTLE_FILE" 2>/dev/null || echo 0)
  if (( now - last <= THROTTLE_SECONDS )); then
    exit 0
  fi
fi
echo "$now" > "$THROTTLE_FILE"

# Reset attention throttle
rm -f "$ATTENTION_THROTTLE_FILE" 2>/dev/null || true

# Read and consume state file (format: "AppName:true" or "AppName:false")
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

state=$(cat "$STATE_FILE" 2>/dev/null || true)
rm -f "$STATE_FILE" 2>/dev/null || true

if [[ -z "$state" ]]; then
  exit 0
fi

# Parse state: everything before last ":" is app name, after is browser state
returnApp="${state%:*}"
browserWasPlaying="${state##*:}"

if [[ -z "$returnApp" ]]; then
  exit 0
fi

if [[ "$returnApp" == "$BROWSER" && "$browserWasPlaying" == "true" ]]; then
  osascript <<EOF 2>/dev/null || true
tell application "$BROWSER"
  activate
  try
    set t to active tab of front window
    -- Seek back and play
    execute t javascript "(() => { document.querySelectorAll('video,audio').forEach(m=>{try{m.currentTime = Math.max(0, m.currentTime - $SEEK_BACK_SECONDS); m.play()}catch(e){}}); })();"
  end try
end tell
EOF
else
  osascript -e "tell application \"$returnApp\" to activate" 2>/dev/null || true
fi
