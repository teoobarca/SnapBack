#!/bin/bash
set -euo pipefail

# Capture current frontmost app BEFORE launching AIAttention
frontmost="$(swift -e 'import AppKit; print(NSWorkspace.shared.frontmostApplication?.localizedName ?? "")' || true)"

# Ignore if already in workflow apps (or ourselves)
if [[ "$frontmost" != "" \
  && "$frontmost" != "Cursor" \
  && "$frontmost" != "Ghostty" \
  && "$frontmost" != "AIAttention" \
  && "$frontmost" != "AIResume" \
  && "$frontmost" != "applet" ]]; then
  printf "%s" "$frontmost" > /tmp/ai_attention_return_app
else
  rm -f /tmp/ai_attention_return_app >/dev/null 2>&1 || true
fi

open -g -a "$HOME/Applications/AIAttention.app"