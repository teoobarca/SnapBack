#!/usr/bin/env bats
# Integration tests for typed CLI wrappers

setup() {
  TMP="$(mktemp -d -t snapback-cli.XXXXXX)"
  export SNAPBACK_CONFIG_FILE="$TMP/config"
  export XDG_CONFIG_HOME="$TMP"
  mkdir -p "$TMP/snapback"
  mv "$TMP/config" "$TMP/snapback/config" 2>/dev/null || true
  export SNAPBACK_CONFIG_FILE="$TMP/snapback/config"
  : > "$SNAPBACK_CONFIG_FILE"
  # Seed known keys so --allow-new isn't needed
  "$BATS_TEST_DIRNAME/../snapback" config set MODE both --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set VOLUME "1.0" --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set BROWSER "Google Chrome" --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set FOCUS_APPS '("Cursor")' --allow-new
  "$BATS_TEST_DIRNAME/../snapback" hooks set none
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "snapback volume 0.5 sets VOLUME" {
  snapback volume 0.5
  [ "$(snapback config get VOLUME)" = "0.5" ]
}

@test "snapback volume rejects > 1" {
  run snapback volume 2.0
  [ "$status" -ne 0 ]
}

@test "snapback browser Arc sets BROWSER" {
  snapback browser Arc
  [ "$(snapback config get BROWSER)" = "Arc" ]
}

@test "snapback focus list prints current apps" {
  run snapback focus list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor"* ]]
}

@test "snapback focus add appends" {
  snapback focus add Ghostty
  run snapback focus list
  [[ "$output" == *"Cursor"* ]]
  [[ "$output" == *"Ghostty"* ]]
}

@test "snapback focus remove drops the app" {
  snapback focus add Ghostty
  snapback focus remove Cursor
  run snapback focus list
  [[ "$output" != *"Cursor"* ]]
  [[ "$output" == *"Ghostty"* ]]
}

@test "snapback focus set replaces the array" {
  snapback focus set Zed Terminal
  run snapback focus list
  [[ "$output" == *"Zed"* ]]
  [[ "$output" == *"Terminal"* ]]
  [[ "$output" != *"Cursor"* ]]
}

@test "snapback test exits 0 when config is valid" {
  # Use a silent sound to avoid terminal noise
  snapback config set NOTIFICATION_SOUND ""
  run snapback test
  [ "$status" -eq 0 ]
}

@test "snapback focus remove refuses to empty the list" {
  snapback focus set Cursor
  run snapback focus remove Cursor
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot remove last"* ]]
  [ "$(snapback focus list)" = "Cursor" ]
}

@test "snapback config show --json emits FOCUS_APPS as JSON array" {
  snapback focus set "Visual Studio Code" "iTerm 2"
  run snapback config show --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"FOCUS_APPS": ['* ]]
  [[ "$output" == *'"Visual Studio Code"'* ]]
  [[ "$output" == *'"iTerm 2"'* ]]
}

@test "snapback mode supports both switches and sound" {
  snapback mode switches
  [ "$(snapback config get MODE)" = "switches" ]

  snapback mode sound
  [ "$(snapback config get MODE)" = "sound" ]

  snapback mode both
  [ "$(snapback config get MODE)" = "both" ]
}

@test "snapback mode accepts full alias as both" {
  snapback mode full
  [ "$(snapback config get MODE)" = "both" ]
}

@test "snapback hooks set/get supports none and multiple providers" {
  snapback hooks set none
  [ "$(snapback hooks get)" = "none" ]

  snapback hooks set claude opencode
  [ "$(snapback hooks get)" = "claude,opencode" ]
}

@test "snapback hooks add/remove updates provider selection" {
  snapback hooks set claude
  snapback hooks add opencode
  [ "$(snapback hooks get)" = "claude,opencode" ]

  snapback hooks remove claude
  [ "$(snapback hooks get)" = "opencode" ]

  snapback hooks remove all
  [ "$(snapback hooks get)" = "none" ]
}

@test "removing the last provider leaves a sourceable config" {
  snapback hooks set claude
  snapback hooks remove claude
  [ "$(snapback hooks get)" = "none" ]

  # The config must stay valid bash — a broken `HOOK_PROVIDERS=(` would make
  # snapback.sh abort under `set -e` on every hook invocation.
  run bash -c "set -euo pipefail; source \"$SNAPBACK_CONFIG_FILE\""
  [ "$status" -eq 0 ]
  grep -qx 'HOOK_PROVIDERS=()' "$SNAPBACK_CONFIG_FILE"
}

@test "claude hook enable preserves entries without .hooks[0].command" {
  # jq's `contains("snapback")` throws on a null — must guard with `// ""`.
  # Seed ~/.claude/settings.json with a hook entry whose command is missing,
  # then enable claude hooks and assert (a) enable succeeds, (b) the foreign
  # entry is preserved, (c) a snapback entry was added.
  mkdir -p "$TMP/home/.claude"
  cat > "$TMP/home/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PermissionRequest": [
      { "matcher": "*", "hooks": [ { "type": "notification", "message": "hi" } ] }
    ]
  }
}
JSON
  run env HOME="$TMP/home" BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME" bash -c '
    set -euo pipefail
    source "$BATS_TEST_DIRNAME/../snapback-lib.sh"
    source "$BATS_TEST_DIRNAME/../snapback-hooks.sh"
    _snapback_hook_enable_claude /usr/local/bin/snapback.sh /usr/local/bin/snapback-resume.sh
  '
  [ "$status" -eq 0 ]
  # Foreign entry preserved, snapback entry appended.
  run jq -r '[.hooks.PermissionRequest[] | .hooks[0].type] | join(",")' "$TMP/home/.claude/settings.json"
  [[ "$output" == *"notification"* ]]
  [[ "$output" == *"command"* ]]
}

@test "snapback.sh tolerates a corrupted config" {
  # Break the config on purpose; snapback.sh must not abort on source.
  # We grep the script for the defensive `source ... || ...` pattern and
  # also verify that a corrupted file doesn't kill a mimicking shell.
  printf '\nHOOK_PROVIDERS=(\n' >> "$SNAPBACK_CONFIG_FILE"
  # Defensive pre-validation must be present in both runtime scripts.
  grep -q '_CFG="$CONFIG_FILE" bash -c' "$BATS_TEST_DIRNAME/../snapback.sh"
  grep -q '_CFG="$CONFIG_FILE" bash -c' "$BATS_TEST_DIRNAME/../snapback-resume.sh"

  # Run snapback.sh with MODE=sound (fast path, no osascript) and an empty
  # sound file. The corrupted config must NOT take down the script.
  mkdir -p "$TMP/override"
  cat > "$TMP/override/config" <<'EOF'
MODE="sound"
NOTIFICATION_SOUND=""
EOF
  # Then concatenate the broken section AFTER the good keys:
  printf '\nHOOK_PROVIDERS=(\n' >> "$TMP/override/config"
  # snapback.sh reads ${XDG_CONFIG_HOME:-$HOME/.config}/snapback/config, so
  # point XDG_CONFIG_HOME at a dir that contains snapback/config.
  mkdir -p "$TMP/xdg/snapback"
  cp "$TMP/override/config" "$TMP/xdg/snapback/config"
  run env XDG_CONFIG_HOME="$TMP/xdg" bash "$BATS_TEST_DIRNAME/../snapback.sh"
  [ "$status" -eq 0 ]
}
