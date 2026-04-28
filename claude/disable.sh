#!/bin/bash
# Remove SnapBack hooks from ~/.claude/settings.json. Idempotent.
set -euo pipefail
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo "Claude Code:  settings not found, nothing to disable"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Claude Code: jq is required (brew install jq)" >&2
  exit 1
fi

if ! grep -q "snapback" "$SETTINGS" 2>/dev/null; then
  echo "Claude Code:  not enabled"
  exit 0
fi

tmp="$(mktemp)"
if ! jq '
  .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) | map(select((.hooks[0].command // "") | contains("snapback") | not))) |
  .hooks.Stop = ((.hooks.Stop // []) | map(select((.hooks[0].command // "") | contains("snapback") | not))) |
  .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select((.hooks[0].command // "") | contains("snapback") | not))) |
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks[0].command // "") | contains("snapback") | not))) |
  if .hooks.PermissionRequest == [] then del(.hooks.PermissionRequest) else . end |
  if .hooks.Stop == [] then del(.hooks.Stop) else . end |
  if .hooks.PostToolUse == [] then del(.hooks.PostToolUse) else . end |
  if .hooks.UserPromptSubmit == [] then del(.hooks.UserPromptSubmit) else . end |
  if .hooks == {} then del(.hooks) else . end
' "$SETTINGS" > "$tmp"; then
  rm -f "$tmp"
  echo "Claude Code: failed to update $SETTINGS (jq error above)" >&2
  exit 1
fi
mv "$tmp" "$SETTINGS"

echo "Claude Code:  hooks removed from $SETTINGS"
