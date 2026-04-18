#!/bin/bash
# snapback-hooks.sh - hook provider registry and operations.
# Sourced by snapback and install.sh.

[[ -n "${SNAPBACK_HOOKS_LIB_LOADED:-}" ]] && return 0
SNAPBACK_HOOKS_LIB_LOADED=1

_snapback_hook_available_providers() {
  printf '%s\n' "claude" "opencode"
}

_snapback_hook_escape_token() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\$/\\\$}"
  v="${v//\`/\\\`}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

_snapback_hook_write_selected() {
  if (( $# == 0 )); then
    config_set HOOK_PROVIDERS "()" --allow-new
    return
  fi
  local literal='('
  local first=1 p
  for p in "$@"; do
    (( first )) || literal+=' '
    first=0
    literal+="$(_snapback_hook_escape_token "$p")"
  done
  literal+=')'
  config_set HOOK_PROVIDERS "$literal" --allow-new
}

# Populates global array: SNAPBACK_HOOK_SELECTED
_snapback_hook_read_selected() {
  SNAPBACK_HOOK_SELECTED=()
  local has_key=0
  if config_get HOOK_PROVIDERS >/dev/null 2>&1; then
    has_key=1
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && SNAPBACK_HOOK_SELECTED+=("$line")
    done < <(config_get HOOK_PROVIDERS)
  fi

  # Backward-compatible default when key is absent.
  if (( has_key == 0 )); then
    SNAPBACK_HOOK_SELECTED=("claude")
  fi
}

_snapback_hook_is_valid_provider() {
  local target="$1"
  local p
  while IFS= read -r p; do
    [[ "$p" == "$target" ]] && return 0
  done < <(_snapback_hook_available_providers)
  return 1
}

_snapback_hook_plugin_path_opencode() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/snapback.js"
}

_snapback_hook_settings_path_claude() {
  printf '%s\n' "$HOME/.claude/settings.json"
}

_snapback_hook_js_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

_snapback_hook_enable_claude() {
  local snapback_path="$1" resume_path="$2"
  local settings
  settings="$(_snapback_hook_settings_path_claude)"
  mkdir -p "$(dirname "$settings")"
  [[ -f "$settings" ]] || printf '{}\n' > "$settings"

  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for Claude hooks (brew install jq)" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg snapback "$snapback_path" --arg resume "$resume_path" '
    .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) | map(select(((.hooks[0].command // "") | contains("snapback")) | not))) + [{"matcher": "*", "hooks": [{"type": "command", "command": $snapback}]}] |
    .hooks.Stop = ((.hooks.Stop // []) | map(select(((.hooks[0].command // "") | contains("snapback")) | not))) + [{"hooks": [{"type": "command", "command": $snapback}]}] |
    .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(((.hooks[0].command // "") | contains("snapback")) | not))) + [{"matcher": "Edit|Write|Bash", "hooks": [{"type": "command", "command": $resume}]}] |
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select(((.hooks[0].command // "") | contains("snapback")) | not))) + [{"hooks": [{"type": "command", "command": $resume}]}]
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
}

_snapback_hook_disable_claude() {
  local settings
  settings="$(_snapback_hook_settings_path_claude)"
  [[ -f "$settings" ]] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for Claude hooks (brew install jq)" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  jq '
    .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) | map(select(((.hooks[0].command // "") | contains("snapback")) | not))) |
    .hooks.Stop = ((.hooks.Stop // []) | map(select(((.hooks[0].command // "") | contains("snapback")) | not))) |
    .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(((.hooks[0].command // "") | contains("snapback")) | not))) |
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select(((.hooks[0].command // "") | contains("snapback")) | not))) |
    if .hooks.PermissionRequest == [] then del(.hooks.PermissionRequest) else . end |
    if .hooks.Stop == [] then del(.hooks.Stop) else . end |
    if .hooks.PostToolUse == [] then del(.hooks.PostToolUse) else . end |
    if .hooks.UserPromptSubmit == [] then del(.hooks.UserPromptSubmit) else . end |
    if .hooks == {} then del(.hooks) else . end
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
}

_snapback_hook_enable_opencode() {
  local snapback_path="$1" resume_path="$2"
  local plugin_path
  plugin_path="$(_snapback_hook_plugin_path_opencode)"
  mkdir -p "$(dirname "$plugin_path")"

  local escaped_snapback escaped_resume
  escaped_snapback="$(_snapback_hook_js_escape "$snapback_path")"
  escaped_resume="$(_snapback_hook_js_escape "$resume_path")"

  cat > "$plugin_path" <<EOF
// snapback-managed: do not edit manually
// Event names verified against sst/opencode packages/plugin/src/index.ts
// and packages/sdk/js/src/gen/types.gen.ts.
import { spawn } from "node:child_process"

const SNAPBACK_ATTENTION = "$escaped_snapback"
const SNAPBACK_RESUME = "$escaped_resume"

const run = (path) => {
  try {
    const child = spawn(path, { stdio: "ignore", detached: true })
    child.on("error", () => {})
    child.unref()
  } catch {
    // Ignore spawn errors; SnapBack CLI reports status separately.
  }
}

export const SnapBackPlugin = async (_ctx) => {
  return {
    // Session/permission events — these are the authoritative attention
    // signals from the opencode SDK Event union.
    event: async ({ event }) => {
      const type = event?.type
      if (type === "session.idle" || type === "permission.updated") {
        run(SNAPBACK_ATTENTION)
      }
    },
    // Called when a new message is received, i.e. the user just submitted
    // a prompt and the agent is about to start working. This is the
    // canonical "resume" trigger, not any TUI-layer command event.
    "chat.message": async (_input, _output) => {
      run(SNAPBACK_RESUME)
    },
    // Every tool invocation also resumes — covers agent-driven follow-ups
    // inside a single turn and is a safety net if chat.message is missed.
    "tool.execute.after": async (_input, _output) => {
      run(SNAPBACK_RESUME)
    },
  }
}
EOF
}

_snapback_hook_disable_opencode() {
  local plugin_path
  plugin_path="$(_snapback_hook_plugin_path_opencode)"

  # Clean up legacy incorrect singular path if present.
  local legacy_path="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugin/snapback.js"
  if [[ -f "$legacy_path" ]] && grep -q "snapback-managed" "$legacy_path" 2>/dev/null; then
    rm -f "$legacy_path"
  fi

  [[ -f "$plugin_path" ]] || return 0

  if grep -q "snapback-managed" "$plugin_path" 2>/dev/null; then
    rm -f "$plugin_path"
    return 0
  fi

  echo "Refusing to remove unmanaged OpenCode plugin: $plugin_path" >&2
  return 1
}

snapback_hooks_set_selected() {
  [[ $# -ge 1 ]] || {
    echo "Usage: snapback hooks set none|all|PROVIDER [PROVIDER ...]" >&2
    return 2
  }

  if [[ "$1" == "none" ]]; then
    [[ $# -eq 1 ]] || {
      echo "'none' cannot be combined with other providers" >&2
      return 2
    }
    config_set HOOK_PROVIDERS "()" --allow-new
    return 0
  fi

  local providers=()
  if [[ "$1" == "all" ]]; then
    [[ $# -eq 1 ]] || {
      echo "'all' cannot be combined with other providers" >&2
      return 2
    }
    local p
    while IFS= read -r p; do providers+=("$p"); done < <(_snapback_hook_available_providers)
  else
    local p seen
    for p in "$@"; do
      _snapback_hook_is_valid_provider "$p" || {
        echo "Unknown provider: $p" >&2
        return 2
      }
      seen=0
      local q
      for q in "${providers[@]+"${providers[@]}"}"; do
        if [[ "$q" == "$p" ]]; then
          seen=1
          break
        fi
      done
      (( seen == 0 )) && providers+=("$p")
    done
  fi

  _snapback_hook_write_selected "${providers[@]+"${providers[@]}"}"
}

snapback_hooks_add_selected() {
  [[ $# -ge 1 ]] || {
    echo "Usage: snapback hooks add all|PROVIDER [PROVIDER ...]" >&2
    return 2
  }

  _snapback_hook_read_selected
  local providers=("${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}")

  local to_add=()
  if [[ "$1" == "all" ]]; then
    [[ $# -eq 1 ]] || {
      echo "'all' cannot be combined with other providers" >&2
      return 2
    }
    local p
    while IFS= read -r p; do to_add+=("$p"); done < <(_snapback_hook_available_providers)
  else
    local p
    for p in "$@"; do
      _snapback_hook_is_valid_provider "$p" || {
        echo "Unknown provider: $p" >&2
        return 2
      }
      to_add+=("$p")
    done
  fi

  local p q seen
  for p in "${to_add[@]+"${to_add[@]}"}"; do
    seen=0
    for q in "${providers[@]+"${providers[@]}"}"; do
      if [[ "$q" == "$p" ]]; then
        seen=1
        break
      fi
    done
    (( seen == 0 )) && providers+=("$p")
  done

  _snapback_hook_write_selected "${providers[@]+"${providers[@]}"}"
}

snapback_hooks_remove_selected() {
  [[ $# -ge 1 ]] || {
    echo "Usage: snapback hooks remove all|PROVIDER [PROVIDER ...]" >&2
    return 2
  }

  _snapback_hook_read_selected
  local providers=("${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}")
  if (( ${#providers[@]} == 0 )); then
    return 0
  fi

  if [[ "$1" == "all" ]]; then
    [[ $# -eq 1 ]] || {
      echo "'all' cannot be combined with other providers" >&2
      return 2
    }
    config_set HOOK_PROVIDERS "()" --allow-new
    return 0
  fi

  local p
  for p in "$@"; do
    _snapback_hook_is_valid_provider "$p" || {
      echo "Unknown provider: $p" >&2
      return 2
    }
  done

  local kept=() drop
  local q remove
  for q in "${providers[@]+"${providers[@]}"}"; do
    remove=0
    for drop in "$@"; do
      if [[ "$q" == "$drop" ]]; then
        remove=1
        break
      fi
    done
    (( remove == 0 )) && kept+=("$q")
  done

  _snapback_hook_write_selected "${kept[@]+"${kept[@]}"}"
}

snapback_hooks_selected_csv() {
  _snapback_hook_read_selected
  if (( ${#SNAPBACK_HOOK_SELECTED[@]} == 0 )); then
    printf 'none\n'
    return 0
  fi

  local out="" p
  for p in "${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}"; do
    [[ -n "$out" ]] && out+=","
    out+="$p"
  done
  printf '%s\n' "$out"
}

snapback_hooks_list_available() {
  _snapback_hook_available_providers
}

_snapback_hook_status_one() {
  local provider="$1"
  case "$provider" in
    claude)
      local settings
      settings="$(_snapback_hook_settings_path_claude)"
      if [[ ! -f "$settings" ]]; then
        printf 'missing|%s\n' "$settings"
      elif grep -q "snapback.sh" "$settings" 2>/dev/null; then
        printf 'enabled|%s\n' "$settings"
      else
        printf 'disabled|%s\n' "$settings"
      fi
      ;;
    opencode)
      local plugin
      plugin="$(_snapback_hook_plugin_path_opencode)"
      if [[ -f "$plugin" ]] && grep -q "snapback-managed" "$plugin" 2>/dev/null; then
        printf 'enabled|%s\n' "$plugin"
      else
        printf 'disabled|%s\n' "$plugin"
      fi
      ;;
    *)
      printf 'error|unknown provider\n'
      ;;
  esac
}

snapback_hooks_enable_selected() {
  local snapback_path="$1" resume_path="$2"
  _snapback_hook_read_selected
  if (( ${#SNAPBACK_HOOK_SELECTED[@]} == 0 )); then
    return 0
  fi

  local p rc=0
  for p in "${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}"; do
    case "$p" in
      claude)
        _snapback_hook_enable_claude "$snapback_path" "$resume_path" || rc=1
        ;;
      opencode)
        _snapback_hook_enable_opencode "$snapback_path" "$resume_path" || rc=1
        ;;
      *)
        echo "Unknown hook provider in config: $p" >&2
        rc=1
        ;;
    esac
  done
  return $rc
}

snapback_hooks_disable_selected() {
  _snapback_hook_read_selected
  if (( ${#SNAPBACK_HOOK_SELECTED[@]} == 0 )); then
    return 0
  fi

  local p rc=0
  for p in "${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}"; do
    case "$p" in
      claude) _snapback_hook_disable_claude || rc=1 ;;
      opencode) _snapback_hook_disable_opencode || rc=1 ;;
      *) echo "Unknown hook provider in config: $p" >&2; rc=1 ;;
    esac
  done
  return $rc
}

snapback_hooks_disable_all() {
  local p rc=0
  while IFS= read -r p; do
    case "$p" in
      claude) _snapback_hook_disable_claude || rc=1 ;;
      opencode) _snapback_hook_disable_opencode || rc=1 ;;
    esac
  done < <(_snapback_hook_available_providers)
  return $rc
}

snapback_hooks_apply_selected() {
  local snapback_path="$1" resume_path="$2"
  snapback_hooks_disable_all || return 1
  snapback_hooks_enable_selected "$snapback_path" "$resume_path"
}

snapback_hooks_status_json() {
  _snapback_hook_read_selected
  local p
  local all_enabled=1
  if (( ${#SNAPBACK_HOOK_SELECTED[@]} == 0 )); then
    all_enabled=0
  fi

  printf '{\n'
  printf '  "selected": ['
  local first=1
  for p in "${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}"; do
    (( first )) || printf ', '
    first=0
    printf '"%s"' "$p"
  done
  printf '],\n'
  printf '  "providers": {\n'
  first=1
  for p in "${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}"; do
    local status detail
    IFS='|' read -r status detail <<< "$(_snapback_hook_status_one "$p")"
    [[ "$status" == "enabled" ]] || all_enabled=0
    (( first )) || printf ',\n'
    first=0
    printf '    "%s": {"status": "%s", "detail": "%s"}' "$p" "$status" "$detail"
  done
  if (( ${#SNAPBACK_HOOK_SELECTED[@]} > 0 )); then
    printf '\n'
  fi
  printf '  },\n'
  if (( all_enabled == 1 )); then
    printf '  "enabled": true\n'
  else
    printf '  "enabled": false\n'
  fi
  printf '}\n'
}

snapback_hooks_any_enabled() {
  _snapback_hook_read_selected
  local p
  for p in "${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}"; do
    local status detail
    IFS='|' read -r status detail <<< "$(_snapback_hook_status_one "$p")"
    [[ "$status" == "enabled" ]] && return 0
  done
  return 1
}

snapback_hooks_status_human() {
  _snapback_hook_read_selected
  if (( ${#SNAPBACK_HOOK_SELECTED[@]} == 0 )); then
    printf 'none\n'
    return 0
  fi

  local p
  for p in "${SNAPBACK_HOOK_SELECTED[@]+"${SNAPBACK_HOOK_SELECTED[@]}"}"; do
    local status detail
    IFS='|' read -r status detail <<< "$(_snapback_hook_status_one "$p")"
    printf '%s\t%s\t%s\n' "$p" "$status" "$detail"
  done
}
