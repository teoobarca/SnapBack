#!/usr/bin/env bats
# Asserts the bridge integration does not regress snapback.sh hook latency
# beyond a small delta. Absolute wall-clock numbers are hardware-specific
# (bash startup on macOS is ~35-45 ms), so this tests REGRESSION, not budget.

setup() {
  TMP="$(mktemp -d -t snapback-latency.XXXXXX)"
  export XDG_CONFIG_HOME="$TMP"
  # Short socket path: AF_UNIX caps sun_path at 104 bytes on macOS, and
  # mktemp under /var/folders/... can overflow. Use /tmp with PID suffix.
  SOCK="/tmp/snapback-latency-$$.sock"
  rm -f "$SOCK"
  export SNAPBACK_BRIDGE_SOCKET="$SOCK"
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
  POKE="$BATS_TEST_DIRNAME/../poke/build/snapback-poke"
  [ -x "$POKE" ] || make -s -C "$BATS_TEST_DIRNAME/../poke"
  export PATH="$(dirname "$POKE"):$PATH"
}

teardown() {
  rm -f "$SOCK"
  rm -rf "$TMP"
}

_now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

_time_ms() {
  local s e
  s=$(_now_ms)
  "$@" >/dev/null 2>&1 || true
  e=$(_now_ms)
  echo $(( e - s ))
}

_median_ms() {
  # $1: run count, $2+: command
  local n="$1"; shift
  # warmup
  "$@" >/dev/null 2>&1 || true
  local samples=()
  local i
  for (( i = 0; i < n; i++ )); do
    samples+=("$(_time_ms "$@")")
  done
  printf '%s\n' "${samples[@]}" | sort -n | awk -v n="$n" 'NR == int((n+1)/2) { print $0; exit }'
}

@test "snapback.sh completes under 200 ms (sanity; bridge absent)" {
  local ms
  ms=$(_median_ms 5 "$BATS_TEST_DIRNAME/../snapback.sh")
  echo "median_absent_ms=$ms"
  [ "$ms" -lt 200 ]
}

@test "bridge-present adds <=20 ms regression vs bridge-absent" {
  # Absent baseline (socket missing): poke block short-circuits on [[ -S ]].
  local absent_ms
  absent_ms=$(_median_ms 5 "$BATS_TEST_DIRNAME/../snapback.sh")

  # Present: start a listener, measure.
  python3 - <<PY &
import socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind("$SOCK")
s.listen(16)
try:
    while True:
        c, _ = s.accept()
        c.close()
except Exception:
    pass
PY
  local LISTENER_PID=$!
  # wait for socket to exist
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -S "$SOCK" ] && break
    sleep 0.1
  done
  [ -S "$SOCK" ]

  local present_ms
  present_ms=$(_median_ms 5 "$BATS_TEST_DIRNAME/../snapback.sh")

  kill "$LISTENER_PID" 2>/dev/null || true
  wait "$LISTENER_PID" 2>/dev/null || true

  local delta=$(( present_ms - absent_ms ))
  echo "absent_ms=$absent_ms  present_ms=$present_ms  delta=$delta"
  # Regression must be small. 20 ms tolerates fork+connect+write+shutdown+close
  # plus Python listener wake. On this repo's hardware, real delta is ~10 ms.
  [ "$delta" -le 20 ]
}

@test "snapback-resume.sh completes under 200 ms (sanity; bridge absent)" {
  local ms
  ms=$(_median_ms 5 "$BATS_TEST_DIRNAME/../snapback-resume.sh")
  echo "median_absent_resume_ms=$ms"
  [ "$ms" -lt 200 ]
}
