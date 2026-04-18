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
  "$BATS_TEST_DIRNAME/../snapback" config set MODE full --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set VOLUME "1.0" --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set BROWSER "Google Chrome" --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set FOCUS_APPS '("Cursor")' --allow-new
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
