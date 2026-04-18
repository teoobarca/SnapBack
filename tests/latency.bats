#!/usr/bin/env bats
# Asserts snapback.sh and snapback-resume.sh do not regress hook latency.

setup() {
  TMP="$(mktemp -d -t snapback-latency.XXXXXX)"
  export XDG_CONFIG_HOME="$TMP"
  export TMPDIR="$TMP"
  mkdir -p "$TMP/snapback"
  cat > "$TMP/snapback/config" <<'EOF'
FOCUS_APPS=()
FOCUS_DELAY=0
BROWSER=""
SEEK_BACK_SECONDS=1
THROTTLE_SECONDS=0
NOTIFICATION_SOUND=""
VOLUME="1.0"
MODE="sound"
EOF
  export SNAPBACK_BRIDGE_SOCKET="$TMP/snapback-bridge.sock"
  POKE="$BATS_TEST_DIRNAME/../poke/build/snapback-poke"
  [ -x "$POKE" ] || make -s -C "$BATS_TEST_DIRNAME/../poke"
  export PATH="$(dirname "$POKE"):$PATH"
}

teardown() {
  rm -rf "$TMP"
}

_time_ms() {
  local start end
  start=$(python3 -c 'import time; print(int(time.time()*1000))')
  "$@" >/dev/null 2>&1 || true
  end=$(python3 -c 'import time; print(int(time.time()*1000))')
  echo $(( end - start ))
}

@test "snapback.sh returns in <=10 ms when bridge is absent" {
  "$BATS_TEST_DIRNAME/../snapback.sh" >/dev/null 2>&1 || true  # warm
  local ms
  ms=$(_time_ms "$BATS_TEST_DIRNAME/../snapback.sh")
  echo "ms=$ms"
  [ "$ms" -le 10 ]
}

@test "snapback-resume.sh returns in <=10 ms when bridge is absent" {
  "$BATS_TEST_DIRNAME/../snapback-resume.sh" >/dev/null 2>&1 || true  # warm
  local ms
  ms=$(_time_ms "$BATS_TEST_DIRNAME/../snapback-resume.sh")
  echo "ms=$ms"
  [ "$ms" -le 10 ]
}
