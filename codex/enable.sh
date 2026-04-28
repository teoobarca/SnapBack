#!/bin/bash
# Register SnapBack as Codex's `notify` command in ~/.codex/config.toml.
# Uses an awk-managed marker block so re-runs are idempotent and other config
# is left untouched. Codex only allows ONE `notify` setting, so if a user
# already has one outside our markers, abort rather than overwrite.
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME_DIR/config.toml"
NOTIFY_PATH="$DIR/codex/notify.sh"
BEGIN_MARKER="# >>> snapback >>>"
END_MARKER="# <<< snapback <<<"

mkdir -p "$CODEX_HOME_DIR"
[ -f "$CONFIG" ] || : > "$CONFIG"

# Refuse to overwrite a user-set `notify =` line that's outside our markers.
conflict="$(awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
  $0==b {in_block=1; next}
  $0==e {in_block=0; next}
  !in_block && /^[[:space:]]*notify[[:space:]]*=/ {print NR": "$0}
' "$CONFIG")"

if [ -n "$conflict" ]; then
  echo "Codex CLI: refusing to overwrite an existing 'notify' in $CONFIG" >&2
  echo "$conflict" | sed 's/^/  /' >&2
  echo "  Codex only supports one notify command. Remove the line above" >&2
  echo "  manually, then re-run 'snapback on'." >&2
  exit 1
fi

# Strip any existing snapback block (idempotent re-runs).
tmp="$(mktemp)"
awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
  $0==b {in_block=1; next}
  $0==e {in_block=0; next}
  !in_block {print}
' "$CONFIG" > "$tmp"

# Trim leading blank lines so re-runs don't accumulate whitespace at the top.
trimmed="$(mktemp)"
awk 'NF || started { started=1; print }' "$tmp" > "$trimmed"
mv "$trimmed" "$tmp"

# Compose final file: our block FIRST (top-level scope, before any [section]
# header), then a blank line, then the user's existing content. TOML keys
# after a [section] belong to that section, so appending at the bottom would
# place `notify` inside whatever the last section was (e.g. [features]) and
# break Codex's config parser.
{
  echo "$BEGIN_MARKER"
  echo "notify = [\"$NOTIFY_PATH\"]"
  echo "$END_MARKER"
  if [ -s "$tmp" ]; then
    echo ""
    cat "$tmp"
  fi
} > "$CONFIG"
rm -f "$tmp"

echo "Codex CLI:    notify registered in $CONFIG"
