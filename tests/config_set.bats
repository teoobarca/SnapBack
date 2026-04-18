#!/usr/bin/env bats
# Tests for snapback-lib.sh config_set / config_get

setup() {
  TMP="$(mktemp -d -t snapback-test.XXXXXX)"
  export SNAPBACK_CONFIG_FILE="$TMP/config"
  : > "$SNAPBACK_CONFIG_FILE"
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../snapback-lib.sh"
}

teardown() {
  rm -rf "$TMP"
}

@test "config_set appends a new scalar key quoted" {
  config_set MODE sound --allow-new
  run cat "$SNAPBACK_CONFIG_FILE"
  [ "$status" -eq 0 ]
  grep -qx 'MODE="sound"' "$SNAPBACK_CONFIG_FILE"
}

@test "config_set replaces an existing scalar key in place" {
  printf 'MODE="full"\n# keep me\nVOLUME="0.5"\n' > "$SNAPBACK_CONFIG_FILE"
  config_set MODE sound
  grep -qx 'MODE="sound"' "$SNAPBACK_CONFIG_FILE"
  grep -qx '# keep me' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'VOLUME="0.5"' "$SNAPBACK_CONFIG_FILE"
}

@test "config_set escapes backslash, dollar, backtick, double-quote" {
  config_set NOTIFICATION_SOUND '/path/with $var `cmd` "q" \back'
  # Sourcing the file must produce the original value
  (
    # shellcheck disable=SC1090
    source "$SNAPBACK_CONFIG_FILE"
    [ "$NOTIFICATION_SOUND" = '/path/with $var `cmd` "q" \back' ]
  )
}

@test "config_set preserves unknown keys and comments" {
  printf '# top comment\nCUSTOM="keep"\nMODE="full"\n' > "$SNAPBACK_CONFIG_FILE"
  config_set MODE sound
  grep -qx '# top comment' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'CUSTOM="keep"' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'MODE="sound"' "$SNAPBACK_CONFIG_FILE"
}

@test "config_set writes FOCUS_APPS as a bash array literal" {
  printf 'FOCUS_APPS=("Old")\nMODE="full"\n' > "$SNAPBACK_CONFIG_FILE"
  # Caller passes pre-formatted literal
  config_set FOCUS_APPS '("Cursor" "Ghostty")'
  grep -qx 'FOCUS_APPS=("Cursor" "Ghostty")' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'MODE="full"' "$SNAPBACK_CONFIG_FILE"
}

@test "config_set serializes concurrent writers via flock" {
  : > "$SNAPBACK_CONFIG_FILE"
  (config_set MODE sound --allow-new) &
  (config_set VOLUME "0.5" --allow-new) &
  wait
  # Both keys must be present
  grep -qx 'MODE="sound"' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'VOLUME="0.5"' "$SNAPBACK_CONFIG_FILE"
}
