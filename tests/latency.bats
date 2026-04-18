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

@test "snapback.sh returns in <=20 ms when bridge is accepting" {
  # macOS AF_UNIX path limit is 104 chars; mktemp dirs are too long for a socket.
  # Use a short fixed path in /tmp, unique per-PID, then restore SNAPBACK_BRIDGE_SOCKET.
  local SHORT_SOCK="/tmp/sb-test-$$.sock"
  export SNAPBACK_BRIDGE_SOCKET="$SHORT_SOCK"
  rm -f "$SHORT_SOCK"
  python3 - <<PY &
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind("$SHORT_SOCK")
s.listen(8)
try:
    while True:
        c, _ = s.accept()
        # drain and close so the client's shutdown/close returns quickly
        c.close()
except Exception:
    pass
PY
  LISTENER_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -S "$SHORT_SOCK" ] && break
    sleep 0.1
  done
  [ -S "$SHORT_SOCK" ]
  "$BATS_TEST_DIRNAME/../snapback.sh" >/dev/null 2>&1 || true  # warm
  local ms
  ms=$(_time_ms "$BATS_TEST_DIRNAME/../snapback.sh")
  kill "$LISTENER_PID" 2>/dev/null || true
  wait "$LISTENER_PID" 2>/dev/null || true
  rm -f "$SHORT_SOCK"
  echo "ms=$ms"
  [ "$ms" -le 20 ]
}
