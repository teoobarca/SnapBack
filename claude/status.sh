#!/bin/bash
# Print one status line. Exit 0 if enabled, 1 otherwise.
SETTINGS="$HOME/.claude/settings.json"

if [ -f "$SETTINGS" ] && grep -q "snapback" "$SETTINGS" 2>/dev/null; then
  echo "Claude Code:  enabled  ($SETTINGS)"
  exit 0
else
  echo "Claude Code:  disabled ($SETTINGS)"
  exit 1
fi
