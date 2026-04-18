#!/bin/bash
# snapback-lib.sh - shared config API for the SnapBack CLI and installer.
# Sourced; do not execute directly.

# Source-once guard
[[ -n "${SNAPBACK_LIB_LOADED:-}" ]] && return 0
SNAPBACK_LIB_LOADED=1

# Config file path (overridable for tests)
: "${SNAPBACK_CONFIG_FILE:=${XDG_CONFIG_HOME:-$HOME/.config}/snapback/config}"

# Known keys table.  Values are type tags: "scalar" or "array".
_snapback_known_keys() {
  cat <<'EOF'
FOCUS_APPS array
FOCUS_DELAY scalar
BROWSER scalar
SEEK_BACK_SECONDS scalar
THROTTLE_SECONDS scalar
NOTIFICATION_SOUND scalar
VOLUME scalar
MODE scalar
EOF
}

_snapback_key_type() {
  local key="$1"
  _snapback_known_keys | awk -v k="$key" '$1 == k { print $2; found=1 } END { exit found ? 0 : 1 }'
}

# Escape a value for writing inside double-quotes in a bash-sourced file.
# Escapes: backslash, dollar, backtick, double-quote.
_snapback_escape_value() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\$/\\\$}"
  v="${v//\`/\\\`}"
  v="${v//\"/\\\"}"
  printf '%s' "$v"
}

# Usage: config_set KEY VALUE [--allow-new]
config_set() {
  local key="$1" value="$2" allow_new=0
  shift 2 || return 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --allow-new) allow_new=1 ;;
      *) echo "config_set: unknown flag: $1" >&2; return 2 ;;
    esac
    shift
  done

  # Validate: key is known, or --allow-new was passed
  local ktype
  if ktype=$(_snapback_key_type "$key"); then
    :
  else
    if (( allow_new == 0 )); then
      echo "config_set: unknown key: $key" >&2
      return 2
    fi
    ktype="scalar"
  fi

  # Validate: no newlines or NULs in value
  if [[ "$value" == *$'\n'* ]]; then
    echo "config_set: value contains newline" >&2
    return 2
  fi

  # Ensure parent dir and file exist
  mkdir -p "$(dirname "$SNAPBACK_CONFIG_FILE")"
  [[ -f "$SNAPBACK_CONFIG_FILE" ]] || : > "$SNAPBACK_CONFIG_FILE"

  if [[ "$ktype" == "scalar" ]]; then
    local escaped
    escaped="$(_snapback_escape_value "$value")"
    # Does the key already exist?
    if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
      # Replace path lands in F1.3.
      echo "config_set: replace path not yet implemented" >&2
      return 3
    else
      printf '\n# Added by snapback config set\n%s="%s"\n' "$key" "$escaped" >> "$SNAPBACK_CONFIG_FILE"
    fi
  else
    echo "config_set: array path not yet implemented" >&2
    return 3
  fi
}
