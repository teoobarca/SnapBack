#!/bin/bash
# Remove the SnapBack-managed block from ~/.codex/config.toml. Idempotent.
set -euo pipefail

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME_DIR/config.toml"
BEGIN_MARKER="# >>> snapback >>>"
END_MARKER="# <<< snapback <<<"
PID_FILE="${TMPDIR:-/tmp}/snapback_codex_watch.pid"

# Always tear down any running resume-watcher.
if [ -f "$PID_FILE" ]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

if [ ! -f "$CONFIG" ]; then
  echo "Codex CLI:    config not found, nothing to disable"
  exit 0
fi

if ! grep -qF "$BEGIN_MARKER" "$CONFIG"; then
  echo "Codex CLI:    not enabled"
  exit 0
fi

tmp="$(mktemp)"
awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
  $0==b {in_block=1; next}
  $0==e {in_block=0; next}
  !in_block {print}
' "$CONFIG" > "$tmp"

# Trim trailing blank lines.
trimmed="$(mktemp)"
awk '/[^[:space:]]/ {print buf $0; buf=""; next} {buf=buf $0 ORS}' "$tmp" > "$trimmed"
mv "$trimmed" "$CONFIG"
rm -f "$tmp"

echo "Codex CLI:    notify removed from $CONFIG"
