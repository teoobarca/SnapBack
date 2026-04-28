#!/bin/bash
# Print one status line. Exit 0 if enabled, 1 otherwise.
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME_DIR/config.toml"
NOTIFY_PATH="$DIR/codex/notify.sh"

if [ -f "$CONFIG" ] && grep -qF "$NOTIFY_PATH" "$CONFIG" 2>/dev/null; then
  echo "Codex CLI:    enabled  ($CONFIG)"
  exit 0
else
  echo "Codex CLI:    disabled ($CONFIG)"
  exit 1
fi
