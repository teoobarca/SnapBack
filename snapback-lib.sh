#!/bin/bash
# snapback-lib.sh - shared config API for the SnapBack CLI and installer.
# Sourced; do not execute directly.

# Source-once guard
[[ -n "${SNAPBACK_LIB_LOADED:-}" ]] && return 0
SNAPBACK_LIB_LOADED=1

# Config file path (overridable for tests)
: "${SNAPBACK_CONFIG_FILE:=${XDG_CONFIG_HOME:-$HOME/.config}/snapback/config}"

# UDS path that hook scripts poke; the bridge daemon listens on the same path.
# Per-user $TMPDIR is used on macOS (avoids collisions across user accounts).
# Strip trailing slash from TMPDIR (macOS appends one) before building the path.
_snapback_tmpdir="${TMPDIR:-/tmp}"
_snapback_tmpdir="${_snapback_tmpdir%/}"
: "${SNAPBACK_BRIDGE_SOCKET:=${_snapback_tmpdir}/snapback-bridge.sock}"
unset _snapback_tmpdir
export SNAPBACK_BRIDGE_SOCKET

# Fire-and-forget poke to the mobile bridge daemon over its Unix socket.
# Silent no-op if the socket or binary is absent. Must never fail the caller,
# even under `set -euo pipefail`. $SCRIPT_DIR is optional; if unset, repo-local
# fallback paths are simply skipped.
# Args: $@ — forwarded verbatim to snapback-poke (e.g. "attention Stop").
snapback_bridge_poke() {
  [[ -S "$SNAPBACK_BRIDGE_SOCKET" ]] || return 0
  local bin="" cand
  if command -v snapback-poke >/dev/null 2>&1; then
    bin="$(command -v snapback-poke)"
  else
    for cand in \
      "$HOME/Applications/SnapBack.app/Contents/MacOS/snapback-poke" \
      "/Applications/SnapBack.app/Contents/MacOS/snapback-poke" \
      "${SCRIPT_DIR:-}/SnapBackApp/SnapBack.app/Contents/MacOS/snapback-poke" \
      "${SCRIPT_DIR:-}/poke/build/snapback-poke"; do
      if [[ -x "$cand" ]]; then
        bin="$cand"
        break
      fi
    done
  fi
  [[ -n "$bin" ]] || return 0
  ( "$bin" "$@" >/dev/null 2>&1 ) &
  disown 2>/dev/null || true
  return 0
}

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
MOBILE_ENABLED scalar
MOBILE_DEVICE_NAME scalar
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

# Rewrite the line that begins with KEY= to be exactly NEW_LINE.
# Reads the file line-by-line in bash (no sed — sed metachars in
# NEW_LINE would break substitution).
_snapback_rewrite_scalar() {
  local key="$1" new_line="$2"
  local tmp
  tmp="$(mktemp "${SNAPBACK_CONFIG_FILE}.tmp.XXXXXX")"
  local line replaced=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( replaced == 0 )) && [[ "$line" == "${key}="* ]]; then
      printf '%s\n' "$new_line" >> "$tmp"
      replaced=1
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$SNAPBACK_CONFIG_FILE"
  mv "$tmp" "$SNAPBACK_CONFIG_FILE"
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

  local lockdir="${SNAPBACK_CONFIG_FILE}.lock.d"
  local waited=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    if (( waited >= 500 )); then
      echo "config_set: lock timeout" >&2
      return 4
    fi
    sleep 0.01
    waited=$((waited + 1))
  done

  # Perform the write in a ( subshell ) so that any set -e abort still
  # triggers the EXIT trap.  The subshell can write to $SNAPBACK_CONFIG_FILE
  # (a real file), so this is safe.  Lock is removed by the EXIT trap inside
  # the subshell OR by the explicit rmdir below if the subshell exits cleanly.
  # (bash 3.2 lacks 'trap RETURN', hence this subshell + EXIT pattern.)
  local _rc=0
  (
    trap 'rmdir "'"$lockdir"'" 2>/dev/null' EXIT
    if [[ "$ktype" == "scalar" ]]; then
      local escaped new_line
      escaped="$(_snapback_escape_value "$value")"
      new_line="${key}=\"${escaped}\""
      if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
        _snapback_rewrite_scalar "$key" "$new_line"
      else
        printf '\n# Added by snapback config set\n%s\n' "$new_line" >> "$SNAPBACK_CONFIG_FILE"
      fi
    else
      if [[ ! "$value" =~ ^\(.*\)$ ]]; then
        echo "config_set: array value must be (\"a\" \"b\" ...)" >&2
        exit 2
      fi
      local new_line="${key}=${value}"
      if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
        _snapback_rewrite_scalar "$key" "$new_line"
      else
        printf '\n# Added by snapback config set\n%s\n' "$new_line" >> "$SNAPBACK_CONFIG_FILE"
      fi
    fi
  ) || _rc=$?
  rmdir "$lockdir" 2>/dev/null || true  # no-op if EXIT trap already removed it
  return $_rc
}

# Usage: config_get KEY
# Prints the value (unquoted) and returns 0 if the key is set; prints
# nothing and returns 1 if the key is absent.
config_get() {
  local key="$1"
  [[ -f "$SNAPBACK_CONFIG_FILE" ]] || return 1
  local found
  found=$(grep -c "^${key}=" "$SNAPBACK_CONFIG_FILE" || true)
  [[ "$found" -gt 0 ]] || return 1
  (
    # shellcheck disable=SC1090
    source "$SNAPBACK_CONFIG_FILE" 2>/dev/null
    # Array: use [*] with ${arr[*]+${arr[*]}} guard so set -u is safe on empty arrays.
    # Tokens are newline-separated (one per line) to preserve tokens containing spaces.
    if declare -p "$key" 2>/dev/null | grep -q 'declare -a'; then
      eval "printf '%s\n' \"\${${key}[@]+\${${key}[@]}}\""
    else
      eval "printf '%s\n' \"\${${key}-}\""
    fi
  )
}
