#!/bin/bash
# Register SnapBack hooks in ~/.claude/settings.json. Idempotent.
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "Claude Code: jq is required (brew install jq)" >&2
  exit 1
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

tmp="$(mktemp)"
if ! jq --arg snapback "$DIR/snapback.sh" --arg resume "$DIR/snapback-resume.sh" '
  .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) | map(select((.hooks[0].command // "") | contains("snapback") | not))) + [{"matcher": "*", "hooks": [{"type": "command", "command": $snapback}]}] |
  .hooks.Stop = ((.hooks.Stop // []) | map(select((.hooks[0].command // "") | contains("snapback") | not))) + [{"hooks": [{"type": "command", "command": $snapback}]}] |
  .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select((.hooks[0].command // "") | contains("snapback") | not))) + [{"matcher": "Edit|Write|Bash", "hooks": [{"type": "command", "command": $resume}]}] |
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks[0].command // "") | contains("snapback") | not))) + [{"hooks": [{"type": "command", "command": $resume}]}]
' "$SETTINGS" > "$tmp"; then
  rm -f "$tmp"
  echo "Claude Code: failed to update $SETTINGS (jq error above)" >&2
  exit 1
fi
mv "$tmp" "$SETTINGS"

echo "Claude Code:  hooks registered in $SETTINGS"
