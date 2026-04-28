#!/bin/bash
# Adapter invoked by Codex's `notify` setting on every event
# (agent-turn-complete, approval-requested). Codex passes a JSON blob as the
# last argv; we ignore it — the existing tool-agnostic snapback.sh handles the
# attention side, and we spawn a background watcher to detect the next user
# message in the active rollout log so we can fire snapback-resume.sh.
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="${TMPDIR:-/tmp}/snapback_codex_watch.pid"
WATCH_TIMEOUT_SECONDS="${SNAPBACK_CODEX_WATCH_TIMEOUT:-1800}"

# 1) Standard attention: pause media, focus IDE, save state.
"$DIR/snapback.sh" || true

# 2) Replace any prior watcher so we never have two racing.
#    Defensive: PIDs get reused on macOS, so verify the PID still exists AND
#    looks like our watcher (a bash subshell) before signalling it.
if [ -f "$PID_FILE" ]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    case "$(ps -o comm= -p "$OLD_PID" 2>/dev/null)" in
      *bash*) kill "$OLD_PID" 2>/dev/null || true ;;
    esac
  fi
  rm -f "$PID_FILE"
fi

# 3) Find the active rollout file (newest by mtime under ~/.codex/sessions).
SESSIONS_DIR="${CODEX_HOME:-$HOME/.codex}/sessions"
[ -d "$SESSIONS_DIR" ] || exit 0

LATEST="$(find "$SESSIONS_DIR" -type f -name 'rollout-*.jsonl' 2>/dev/null \
  | xargs -I {} stat -f '%m %N' {} 2>/dev/null \
  | sort -rn | head -n1 | cut -d' ' -f2-)"

[ -n "$LATEST" ] && [ -f "$LATEST" ] || exit 0

# 4) Spawn detached watcher: tail -F until first "user_message" line, then
#    fire resume and exit. Self-timeout prevents leaks if Codex closes silently.
#    Uses a FIFO so we can run the while-loop in the main subshell and kill
#    tail/timer cleanly when we break out.
(
  exec </dev/null >/dev/null 2>&1
  FIFO="$(mktemp -u "${TMPDIR:-/tmp}/snapback_codex_fifo.XXXXXX")"
  mkfifo "$FIFO" 2>/dev/null || exit 0

  TAIL_PID=""
  TIMER_PID=""
  # Clean up children, FIFO, and PID file on ANY exit path — including SIGTERM
  # from a successor notify.sh, otherwise tail/timer get orphaned to launchd.
  trap 'kill "$TAIL_PID" "$TIMER_PID" 2>/dev/null; rm -f "$FIFO" "$PID_FILE"' EXIT INT TERM HUP

  tail -n0 -F "$LATEST" >"$FIFO" 2>/dev/null &
  TAIL_PID=$!
  ( sleep "$WATCH_TIMEOUT_SECONDS"; kill -TERM "$TAIL_PID" 2>/dev/null ) &
  TIMER_PID=$!

  while IFS= read -r line; do
    case "$line" in
      *'"type":"user_message"'*)
        "$DIR/snapback-resume.sh" || true
        break
        ;;
    esac
  done < "$FIFO"
  # Trap will kill TAIL_PID/TIMER_PID and clean up files on exit.
) &
WATCH_PID=$!
echo "$WATCH_PID" > "$PID_FILE"
disown "$WATCH_PID" 2>/dev/null || true

exit 0
