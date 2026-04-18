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
