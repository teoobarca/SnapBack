#!/usr/bin/env bats
# Behavioural tests for the snapback-poke helper.

setup() {
  TMP="$(mktemp -d -t snapback-poke.XXXXXX)"
  export TMPDIR="$TMP"
  export SNAPBACK_BRIDGE_SOCKET="$TMP/snapback-bridge.sock"
  POKE="$BATS_TEST_DIRNAME/../poke/build/snapback-poke"
  [ -x "$POKE" ] || (make -C "$BATS_TEST_DIRNAME/../poke" >/dev/null)
}

teardown() {
  rm -rf "$TMP"
}

# Start a tiny python listener that writes whatever it reads to $OUT and exits.
_start_listener() {
  OUT="$TMP/received"
  python3 - <<PY &
import os, socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind("$SNAPBACK_BRIDGE_SOCKET")
s.listen(1)
with open("$OUT", "wb") as f:
    c, _ = s.accept()
    while True:
        b = c.recv(4096)
        if not b: break
        f.write(b)
s.close()
PY
  LISTENER_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -S "$SNAPBACK_BRIDGE_SOCKET" ] && break
    sleep 0.1
  done
  [ -S "$SNAPBACK_BRIDGE_SOCKET" ]
}

_wait_for_output() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$OUT" ] && return 0
    sleep 0.1
  done
  return 1
}

@test "snapback-poke writes '<type>\t<kind>\n' when both args given" {
  _start_listener
  "$POKE" attention PermissionRequest
  wait "$LISTENER_PID"
  _wait_for_output
  run cat "$OUT"
  [ "$output" = $'attention\tPermissionRequest' ]
}

@test "snapback-poke writes '<type>\n' when only type is given" {
  _start_listener
  "$POKE" resume
  wait "$LISTENER_PID"
  _wait_for_output
  run cat "$OUT"
  [ "$output" = "resume" ]
}

@test "snapback-poke exits 0 when the socket file does not exist" {
  run "$POKE" attention PermissionRequest
  [ "$status" -eq 0 ]
}

@test "snapback-poke exits 0 when the socket file exists but nothing is listening" {
  python3 -c "import socket, os; s=socket.socket(socket.AF_UNIX); s.bind('$SNAPBACK_BRIDGE_SOCKET'); s.close()"
  run "$POKE" resume
  [ "$status" -eq 0 ]
}

@test "snapback-poke exits 0 with no arguments" {
  run "$POKE"
  [ "$status" -eq 0 ]
}
