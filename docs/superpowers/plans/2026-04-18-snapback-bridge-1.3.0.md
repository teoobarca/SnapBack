# SnapBack 1.3.0 — Desktop Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship SnapBack 1.3.0: a persistent desktop bridge daemon inside SnapBackApp that exposes a Unix-domain socket for hook scripts, speaks a frozen LAN protocol (HMAC-signed JSON over TCP with mDNS discovery) to a future Android peer, and adds the menu-bar Mobile pairing UI plus CLI subcommands — all without any perceptible hook-latency regression. No phone app is built in 1.3.0; the protocol is exercised against a Swift test fake.

**Architecture:** `snapback.sh` / `snapback-resume.sh` invoke a small C helper (`snapback-poke`) that writes one framed line to a Unix-domain socket and exits. The socket is served by a Swift bridge daemon running inside SnapBackApp (Network.framework end-to-end). The bridge owns a persistent TCP connection to the paired phone, signs messages with HMAC-SHA256 over a canonical, direction-tagged domain, and publishes connection state to the menu-bar UI. Pair tokens live in the macOS Keychain (not the config file). Everything is driven by the existing `snapback-lib.sh` config API, plus two new known-keys rows.

**Tech Stack:** Swift 5.9 (`SnapBackApp` target, macOS 13+), `Network.framework` (NWBrowser/NWListener/NWConnection), `Security.framework` (Keychain), `CryptoKit` (HMAC-SHA256), `CoreImage` (`CIQRCodeGenerator` for the pairing QR), C11 (`snapback-poke` helper), Bash 3.2 (hook scripts), Bats (shell tests), XCTest (Swift tests), `jq` (existing dependency).

**Spec:** `docs/superpowers/specs/2026-04-18-mobile-companion-design.md` — this plan implements §5.1, §5.2, §5.5, §5.6, §5.7, §8.1 (the 1.3.0 bridge-only rollout). The Android 1.4.0 app is a separate plan.

**Key invariants that every task must preserve:**
- Hooks never block on the bridge. Parent-hook wall time ≤10 ms bridge-absent, ≤20 ms bridge-present.
- No plaintext secrets in `~/.config/snapback/config`. Pair token lives only in Keychain.
- HMAC domain matches the spec **byte for byte**. Both sides (Swift + future Android) ship against `tests/protocol-vectors.json`.
- Existing SnapBack behaviour (sound, focus, resume) is untouched. All changes are additive.
- Bash 3.2 compatibility (existing constraint): no `${var,,}`, no associative arrays, no `mapfile`, no `|&`.

---

## File Structure

**Create:**
- `poke/snapback-poke.c` — C11 helper, ~60 lines, builds with `clang`. Opens `$SNAPBACK_BRIDGE_SOCKET`, writes one TSV-ish line, closes, exits.
- `poke/Makefile` — builds `snapback-poke` binary into `poke/build/`.
- `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeServer.swift` — UDS `NWListener`, parses TSV lines, pushes events into the queue.
- `SnapBackApp/Sources/SnapBackApp/Bridge/MobilePeer.swift` — `NWConnection` to paired phone, reconnect with backoff.
- `SnapBackApp/Sources/SnapBackApp/Bridge/MDNSBrowser.swift` — `NWBrowser` on `_snapback._tcp.local`, re-arms on `NWPathMonitor` updates.
- `SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift` — JSON encode/decode + HMAC sign/verify per spec §4.1.
- `SnapBackApp/Sources/SnapBackApp/Bridge/NonceCache.swift` — LRU of seen nonces (receive path only).
- `SnapBackApp/Sources/SnapBackApp/Bridge/EventQueue.swift` — bounded queue + retry/backoff.
- `SnapBackApp/Sources/SnapBackApp/Bridge/HeartbeatLoop.swift` — heartbeat scheduler while `holdOutstanding == true`.
- `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeOrchestrator.swift` — wires everything together, owns state machine, status publisher.
- `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeStatus.swift` — enum + `ObservableObject` published to menu-bar.
- `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeLog.swift` — rolling log writer.
- `SnapBackApp/Sources/SnapBackApp/Bridge/KeychainTokenStore.swift` — wraps Security.framework for pair-token storage.
- `SnapBackApp/Sources/SnapBackApp/Bridge/Pairing.swift` — token generation, QR payload construction.
- `SnapBackApp/Sources/SnapBackApp/Views/MobileTabView.swift` — menu-bar "Mobile" section (status dot, pair button, QR display, unpair).
- `SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift`
- `SnapBackApp/Tests/BridgeTests/NonceCacheTests.swift`
- `SnapBackApp/Tests/BridgeTests/EventQueueTests.swift`
- `SnapBackApp/Tests/BridgeTests/BridgeServerTests.swift`
- `SnapBackApp/Tests/BridgeTests/MobilePeerTests.swift`
- `SnapBackApp/Tests/BridgeTests/BridgeOrchestratorTests.swift`
- `SnapBackApp/Tests/BridgeTests/ProtocolVectorsTests.swift`
- `SnapBackApp/Tests/BridgeTests/TestFakePhone.swift` — in-process peer double.
- `tests/protocol-vectors.json` — shared fixture, read by Swift tests today and Kotlin tests in 1.4.0.
- `tests/latency.bats` — asserts `snapback.sh` wall time in both modes.
- `tests/snapback_poke.bats` — poke helper behaviour (socket missing/refused/accepted).
- `docs/PROTOCOL.md` — frozen wire protocol reference.

**Modify:**
- `snapback-lib.sh:13-24` — add `MOBILE_ENABLED` / `MOBILE_DEVICE_NAME` rows; export `SNAPBACK_BRIDGE_SOCKET`.
- `snapback.sh:145-146` (tail of the file) — append the `snapback-poke attention …` fire-and-forget line.
- `snapback-resume.sh:67-68` (tail of the file) — append the `snapback-poke resume` fire-and-forget line.
- `snapback:5` — bump `VERSION="1.3.0"`.
- `snapback:50-81` (inside `show_help`) — add the `mobile` command row.
- `snapback:739-796` (main dispatcher) — add the `mobile` case.
- `snapback:260` and surrounding — add a new `cmd_mobile` function block.
- `snapback:310-383` (`cmd_uninstall`) — delete Keychain token entry as part of cleanup.
- `SnapBackApp/Package.swift` — add `Security` / `CryptoKit` / `Network` usage (implicit, but we add a test target).
- `SnapBackApp/build-app.sh:6-9` — bump `CFBundleVersion` / `CFBundleShortVersionString` to `1.3.0`; also copy `snapback-poke` binary next to the bundle.
- `SnapBackApp/Sources/SnapBackApp/SnapBackApp.swift` — instantiate the `BridgeOrchestrator` on app launch and pass it to the menu-bar view.
- `SnapBackApp/Sources/SnapBackApp/Views/MenuBarView.swift` — embed `MobileTabView`.
- `SnapBackApp/Sources/SnapBackApp/Models/AppState.swift` — expose the bridge status through the existing `AppState` if it already aggregates UI state, otherwise leave untouched.
- `install.sh` (whichever tail adds CLI symlinks) — install `snapback-poke` into `/usr/local/bin/` alongside the CLI.
- `get.sh` — bundle `poke/` when fetching the tarball.
- `README.md` — add a "Mobile (experimental, 1.3.0 preview)" section pointing to the Android plan.

**Delete:** none.

---

## Phase 0 — Preflight: sanity on `main`

### Task 0.1: Verify working tree is clean before starting

**Files:** none

- [ ] **Step 1: Check working tree**

Run: `git status`
Expected: `nothing to commit, working tree clean`

- [ ] **Step 2: Confirm on `main`**

Run: `git branch --show-current`
Expected: `main`

- [ ] **Step 3: Pull latest**

Run: `git pull --ff-only`
Expected: `Already up to date.` or fast-forward.

If the tree is dirty or the branch is wrong, stop and resolve before touching any files.

---

## Phase 1 — Config keys and socket path

### Task 1.1: Add `MOBILE_ENABLED` and `MOBILE_DEVICE_NAME` to the known-keys table (TDD)

**Files:**
- Modify: `snapback-lib.sh:13-24`
- Test: `tests/config_set.bats`

- [ ] **Step 1: Open `tests/config_set.bats` and add the failing test at the end of the file**

Append:

```bash
@test "config_set accepts MOBILE_ENABLED without --allow-new" {
  run bash -c "source '$BATS_TEST_DIRNAME/../snapback-lib.sh' && config_set MOBILE_ENABLED true"
  [ "$status" -eq 0 ]
  run grep -q '^MOBILE_ENABLED=' "$SNAPBACK_CONFIG_FILE"
  [ "$status" -eq 0 ]
}

@test "config_set accepts MOBILE_DEVICE_NAME without --allow-new" {
  run bash -c "source '$BATS_TEST_DIRNAME/../snapback-lib.sh' && config_set MOBILE_DEVICE_NAME 'Samsung S24'"
  [ "$status" -eq 0 ]
  run bash -c "source '$BATS_TEST_DIRNAME/../snapback-lib.sh' && config_get MOBILE_DEVICE_NAME"
  [ "$status" -eq 0 ]
  [ "$output" = "Samsung S24" ]
}
```

- [ ] **Step 2: Run the new tests to confirm they fail with the current known-keys table**

Run: `bats tests/config_set.bats`
Expected: the two new cases fail with `config_set: unknown key: MOBILE_ENABLED` (and similar for `MOBILE_DEVICE_NAME`). All other tests in the file still pass.

- [ ] **Step 3: Add the two rows in `snapback-lib.sh`**

Edit `snapback-lib.sh:13-24`. Change the heredoc body to:

```bash
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
```

- [ ] **Step 4: Run the full `config_set.bats` suite to verify it passes**

Run: `bats tests/config_set.bats`
Expected: all tests pass, including the two new ones.

- [ ] **Step 5: Commit**

```bash
git add snapback-lib.sh tests/config_set.bats
git commit -m "feat(bridge): register MOBILE_ENABLED and MOBILE_DEVICE_NAME as known config keys"
```

### Task 1.2: Export `SNAPBACK_BRIDGE_SOCKET` from the library (TDD)

**Files:**
- Modify: `snapback-lib.sh:10`
- Test: `tests/config_set.bats`

- [ ] **Step 1: Add the failing test**

Append to `tests/config_set.bats`:

```bash
@test "snapback-lib.sh exports SNAPBACK_BRIDGE_SOCKET with a \$TMPDIR-based default" {
  run bash -c "source '$BATS_TEST_DIRNAME/../snapback-lib.sh' && printf '%s' \"\${SNAPBACK_BRIDGE_SOCKET}\""
  [ "$status" -eq 0 ]
  # Must end with /snapback-bridge.sock
  [[ "$output" == */snapback-bridge.sock ]]
  # Must live inside $TMPDIR when $TMPDIR is set
  if [[ -n "${TMPDIR:-}" ]]; then
    [[ "$output" == "${TMPDIR%/}"/snapback-bridge.sock ]]
  fi
}
```

- [ ] **Step 2: Run it to confirm fail**

Run: `bats tests/config_set.bats`
Expected: the new case fails because `SNAPBACK_BRIDGE_SOCKET` is not set.

- [ ] **Step 3: Add the export in `snapback-lib.sh`**

Insert right after line 10 (`: "${SNAPBACK_CONFIG_FILE:=${XDG_CONFIG_HOME:-$HOME/.config}/snapback/config}"`):

```bash
# UDS path that hook scripts poke; the bridge daemon listens on the same path.
# Per-user $TMPDIR is used on macOS (avoids collisions across user accounts).
: "${SNAPBACK_BRIDGE_SOCKET:=${TMPDIR:-/tmp}/snapback-bridge.sock}"
export SNAPBACK_BRIDGE_SOCKET
```

- [ ] **Step 4: Run the suite**

Run: `bats tests/config_set.bats`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add snapback-lib.sh tests/config_set.bats
git commit -m "feat(bridge): export SNAPBACK_BRIDGE_SOCKET from snapback-lib.sh"
```

---

## Phase 2 — `snapback-poke` helper binary

### Task 2.1: Create the `poke/` directory and a stub `snapback-poke.c`

**Files:**
- Create: `poke/snapback-poke.c`
- Create: `poke/Makefile`

- [ ] **Step 1: Write `poke/snapback-poke.c`**

```c
/*
 * snapback-poke — fire-and-forget Unix-domain poker.
 *
 * Usage: snapback-poke <type> [hook_kind]
 *   <type>       one of: attention, resume, heartbeat-ping
 *   [hook_kind]  optional token (PermissionRequest | Stop); included for attention
 *
 * Reads $SNAPBACK_BRIDGE_SOCKET; falls back to ${TMPDIR:-/tmp}/snapback-bridge.sock.
 * Writes one line: "<type>\t<hook_kind?>\n" and closes.
 * Silent on every error path. Always exits 0. The hook MUST NOT notice us.
 */

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

static void resolve_socket_path(char *out, size_t cap) {
    const char *env = getenv("SNAPBACK_BRIDGE_SOCKET");
    if (env && *env) {
        snprintf(out, cap, "%s", env);
        return;
    }
    const char *tmp = getenv("TMPDIR");
    if (!tmp || !*tmp) tmp = "/tmp";
    /* strip a trailing slash if present */
    size_t n = strlen(tmp);
    while (n > 1 && tmp[n - 1] == '/') n--;
    snprintf(out, cap, "%.*s/snapback-bridge.sock", (int)n, tmp);
}

int main(int argc, char **argv) {
    if (argc < 2) return 0; /* silent */
    const char *type = argv[1];
    const char *kind = argc >= 3 ? argv[2] : "";

    char path[512];
    resolve_socket_path(path, sizeof(path));

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return 0;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof(addr.sun_path)) { close(fd); return 0; }
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return 0;
    }

    char buf[256];
    int n;
    if (kind && *kind)
        n = snprintf(buf, sizeof(buf), "%s\t%s\n", type, kind);
    else
        n = snprintf(buf, sizeof(buf), "%s\n", type);

    if (n > 0 && n < (int)sizeof(buf)) {
        ssize_t written = 0;
        while (written < n) {
            ssize_t w = write(fd, buf + written, (size_t)(n - written));
            if (w < 0) { if (errno == EINTR) continue; break; }
            written += w;
        }
    }
    /* Graceful shutdown: tell peer we are done writing. */
    shutdown(fd, SHUT_WR);
    close(fd);
    return 0;
}
```

- [ ] **Step 2: Write `poke/Makefile`**

```makefile
# snapback-poke — tiny UDS poker for SnapBack hook scripts.
CC      ?= clang
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra -Wpedantic
BUILD   := build
BIN     := $(BUILD)/snapback-poke

.PHONY: all clean install

all: $(BIN)

$(BIN): snapback-poke.c
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $< -o $@

clean:
	rm -rf $(BUILD)

install: $(BIN)
	install -m 0755 $(BIN) $(DESTDIR)/usr/local/bin/snapback-poke
```

- [ ] **Step 3: Build it to make sure it compiles**

Run: `make -C poke`
Expected: `clang -O2 -std=c11 -Wall -Wextra -Wpedantic snapback-poke.c -o build/snapback-poke` with no warnings.

- [ ] **Step 4: Confirm it runs with no socket present without erroring**

Run: `SNAPBACK_BRIDGE_SOCKET=/nonexistent poke/build/snapback-poke attention PermissionRequest; echo $?`
Expected: `0`

- [ ] **Step 5: Commit**

```bash
git add poke/snapback-poke.c poke/Makefile
git commit -m "feat(bridge): add snapback-poke C helper (minimal UDS write-and-exit)"
```

### Task 2.2: Bats test — `snapback-poke` accepted path (TDD)

**Files:**
- Create: `tests/snapback_poke.bats`

- [ ] **Step 1: Write the test file**

```bash
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
  # Wait up to 2 s for the socket to appear
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
```

- [ ] **Step 2: Run the tests**

Run: `bats tests/snapback_poke.bats`
Expected: both tests pass (the helper from Task 2.1 was built correctly).

- [ ] **Step 3: Commit**

```bash
git add tests/snapback_poke.bats
git commit -m "test(bridge): bats coverage for snapback-poke happy paths"
```

### Task 2.3: Bats test — `snapback-poke` behaves silently when socket is missing/refused (TDD)

**Files:**
- Modify: `tests/snapback_poke.bats`

- [ ] **Step 1: Append these cases**

```bash
@test "snapback-poke exits 0 when the socket file does not exist" {
  run "$POKE" attention PermissionRequest
  [ "$status" -eq 0 ]
}

@test "snapback-poke exits 0 when the socket file exists but nothing is listening" {
  # Create a dangling socket file (no server).
  python3 -c "import socket, os; s=socket.socket(socket.AF_UNIX); s.bind('$SNAPBACK_BRIDGE_SOCKET'); s.close()"
  run "$POKE" resume
  [ "$status" -eq 0 ]
}

@test "snapback-poke exits 0 with no arguments" {
  run "$POKE"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the tests**

Run: `bats tests/snapback_poke.bats`
Expected: all 5 tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/snapback_poke.bats
git commit -m "test(bridge): snapback-poke is silent under all failure modes"
```

### Task 2.4: Wire the build into the menu-bar `build-app.sh`

**Files:**
- Modify: `SnapBackApp/build-app.sh`

- [ ] **Step 1: Edit `build-app.sh` and insert, right after `swift build -c release` (around line 15), the following block:**

```bash
# Build the snapback-poke helper (C, no Swift deps).
POKE_SRC_DIR="$SCRIPT_DIR/../poke"
if [[ -d "$POKE_SRC_DIR" ]]; then
  echo "Building snapback-poke..."
  ( cd "$POKE_SRC_DIR" && make -s )
  cp "$POKE_SRC_DIR/build/snapback-poke" "$APP_BUNDLE/Contents/MacOS/snapback-poke"
  chmod +x "$APP_BUNDLE/Contents/MacOS/snapback-poke"
  echo "✓ Bundled snapback-poke"
fi
```

- [ ] **Step 2: Also bump the version — change**

```
<key>CFBundleVersion</key>
<string>1.2</string>
<key>CFBundleShortVersionString</key>
<string>1.2</string>
```

**to**

```
<key>CFBundleVersion</key>
<string>1.3.0</string>
<key>CFBundleShortVersionString</key>
<string>1.3.0</string>
```

- [ ] **Step 3: Run the full build end-to-end**

Run: `cd SnapBackApp && ./build-app.sh`
Expected: Swift builds cleanly; `snapback-poke` is copied; the script prints `✓ Built: …/SnapBack.app` at the end.

- [ ] **Step 4: Confirm the helper is inside the bundle**

Run: `ls -l SnapBackApp/SnapBack.app/Contents/MacOS/`
Expected: lists both `SnapBack` and `snapback-poke`, both executable.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/build-app.sh
git commit -m "build(bridge): bundle snapback-poke inside SnapBack.app; bump CFBundleVersion to 1.3.0"
```

### Task 2.5: `install.sh` symlink for `snapback-poke`

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Open `install.sh`, find the block that creates the `snapback` symlink in `/usr/local/bin/` or `~/.local/bin/`, and add a parallel block for `snapback-poke`.** The exact line numbers depend on the current `install.sh`, but the pattern is: whatever the installer does for `snapback`, do the same for the file `$SCRIPT_DIR/poke/build/snapback-poke`, but only after running `make -C "$SCRIPT_DIR/poke"` to ensure it's built.

The resulting block looks like:

```bash
# Build and install the poke helper.
if [[ -d "$SCRIPT_DIR/poke" ]]; then
  if command -v make >/dev/null 2>&1 && command -v clang >/dev/null 2>&1; then
    ( cd "$SCRIPT_DIR/poke" && make -s ) || {
      echo "warning: snapback-poke failed to build; bridge feature will be inert" >&2
    }
    if [[ -x "$SCRIPT_DIR/poke/build/snapback-poke" ]]; then
      if [[ -w /usr/local/bin ]]; then
        ln -sf "$SCRIPT_DIR/poke/build/snapback-poke" /usr/local/bin/snapback-poke
      else
        sudo ln -sf "$SCRIPT_DIR/poke/build/snapback-poke" /usr/local/bin/snapback-poke
      fi
    fi
  else
    echo "warning: clang+make not available; snapback-poke not built" >&2
  fi
fi
```

- [ ] **Step 2: Run the installer in a dry-ish way — at least confirm bash -n parses it**

Run: `bash -n install.sh`
Expected: no output (no syntax errors).

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "build(bridge): install.sh builds and symlinks snapback-poke"
```

---

## Phase 3 — Hook integration

### Task 3.1: Append the poke line to `snapback.sh` (TDD via latency test)

**Files:**
- Modify: `snapback.sh` (append at end of file)

- [ ] **Step 1: Write a failing latency test in a new file `tests/latency.bats`**

```bash
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
  # Put snapback-poke on PATH for the hook script
  POKE="$BATS_TEST_DIRNAME/../poke/build/snapback-poke"
  [ -x "$POKE" ] || make -s -C "$BATS_TEST_DIRNAME/../poke"
  export PATH="$(dirname "$POKE"):$PATH"
}

teardown() {
  rm -rf "$TMP"
}

_time_ms() {
  # Wall-clock ms of the command passed as arguments.
  local start end
  start=$(python3 -c 'import time; print(int(time.time()*1000))')
  "$@" >/dev/null 2>&1 || true
  end=$(python3 -c 'import time; print(int(time.time()*1000))')
  echo $(( end - start ))
}

@test "snapback.sh returns in <=10 ms when bridge is absent" {
  # Warm the filesystem cache first.
  "$BATS_TEST_DIRNAME/../snapback.sh" >/dev/null 2>&1 || true
  local ms
  ms=$(_time_ms "$BATS_TEST_DIRNAME/../snapback.sh")
  echo "ms=$ms"
  [ "$ms" -le 10 ]
}

@test "snapback-resume.sh returns in <=10 ms when bridge is absent" {
  "$BATS_TEST_DIRNAME/../snapback-resume.sh" >/dev/null 2>&1 || true
  local ms
  ms=$(_time_ms "$BATS_TEST_DIRNAME/../snapback-resume.sh")
  echo "ms=$ms"
  [ "$ms" -le 10 ]
}
```

*(The tests already pass today because no bridge line is present — but they lock in the latency envelope before we modify the hook scripts.)*

- [ ] **Step 2: Run it to confirm green baseline**

Run: `bats tests/latency.bats`
Expected: both tests pass.

- [ ] **Step 3: Append the poke invocation to `snapback.sh`**

Open `snapback.sh`. After the final `EOF` on line 146, append:

```bash

# Bridge integration (1.3.0+): silently poke the mobile bridge daemon.
# Fire-and-forget; zero impact when the socket is absent.
: "${SNAPBACK_BRIDGE_SOCKET:=${TMPDIR:-/tmp}/snapback-bridge.sock}"
if [[ -S "$SNAPBACK_BRIDGE_SOCKET" ]] && command -v snapback-poke >/dev/null 2>&1; then
  ( snapback-poke attention PermissionRequest >/dev/null 2>&1 ) &
  disown
fi
```

- [ ] **Step 4: Re-run the latency test**

Run: `bats tests/latency.bats`
Expected: both tests still pass (no regression — the bridge-absent path is a single `[[ -S ... ]]` check that short-circuits).

- [ ] **Step 5: Commit**

```bash
git add snapback.sh tests/latency.bats
git commit -m "feat(bridge): hook snapback.sh into snapback-poke when bridge socket is present"
```

### Task 3.2: Append the poke line to `snapback-resume.sh`

**Files:**
- Modify: `snapback-resume.sh`

- [ ] **Step 1: At the end of `snapback-resume.sh`, append**

```bash

# Bridge integration (1.3.0+): let the mobile bridge know Claude resumed work.
: "${SNAPBACK_BRIDGE_SOCKET:=${TMPDIR:-/tmp}/snapback-bridge.sock}"
if [[ -S "$SNAPBACK_BRIDGE_SOCKET" ]] && command -v snapback-poke >/dev/null 2>&1; then
  ( snapback-poke resume >/dev/null 2>&1 ) &
  disown
fi
```

- [ ] **Step 2: Run latency tests**

Run: `bats tests/latency.bats`
Expected: both tests pass.

- [ ] **Step 3: Commit**

```bash
git add snapback-resume.sh
git commit -m "feat(bridge): hook snapback-resume.sh into snapback-poke on resume"
```

### Task 3.3: Bridge-present latency test (TDD)

**Files:**
- Modify: `tests/latency.bats`

- [ ] **Step 1: Append the new case that spawns a trivial listener and measures the hooks**

```bash
@test "snapback.sh returns in <=20 ms when bridge is accepting" {
  # Tiny listener — accept-and-drain forever until killed.
  python3 - <<PY &
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind("$SNAPBACK_BRIDGE_SOCKET")
s.listen(8)
s.settimeout(None)
conns = []
try:
    while True:
        c, _ = s.accept()
        conns.append(c)
        # We don't read — draining would add latency we don't want to measure.
        # Hook's shutdown() + close() is all we care about.
except Exception:
    pass
PY
  LISTENER_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -S "$SNAPBACK_BRIDGE_SOCKET" ] && break
    sleep 0.1
  done
  [ -S "$SNAPBACK_BRIDGE_SOCKET" ]
  # Warm cache once.
  "$BATS_TEST_DIRNAME/../snapback.sh" >/dev/null 2>&1 || true
  local ms
  ms=$(_time_ms "$BATS_TEST_DIRNAME/../snapback.sh")
  kill "$LISTENER_PID" 2>/dev/null || true
  echo "ms=$ms"
  [ "$ms" -le 20 ]
}
```

- [ ] **Step 2: Run it**

Run: `bats tests/latency.bats`
Expected: the new test passes (fork + UDS connect + 40-byte write typically measures 2–6 ms warm).

- [ ] **Step 3: Commit**

```bash
git add tests/latency.bats
git commit -m "test(bridge): latency stays <=20 ms when the bridge is accepting"
```

---

## Phase 4 — Swift test target scaffolding

### Task 4.1: Add a test target to `SnapBackApp/Package.swift`

**Files:**
- Modify: `SnapBackApp/Package.swift`
- Create: `SnapBackApp/Tests/BridgeTests/SmokeTest.swift`

- [ ] **Step 1: Replace `SnapBackApp/Package.swift` with**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapBackApp",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SnapBackApp",
            path: "Sources/SnapBackApp"
        ),
        .testTarget(
            name: "BridgeTests",
            dependencies: ["SnapBackApp"],
            path: "Tests/BridgeTests",
            resources: [
                .copy("fixtures")
            ]
        )
    ]
)
```

- [ ] **Step 2: Create `SnapBackApp/Tests/BridgeTests/SmokeTest.swift`**

```swift
import XCTest
@testable import SnapBackApp

final class SmokeTest: XCTestCase {
    func testHarnessBuilds() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

- [ ] **Step 3: Create the fixtures directory so the resource copy rule is happy**

Run: `mkdir -p SnapBackApp/Tests/BridgeTests/fixtures`
Run: `touch SnapBackApp/Tests/BridgeTests/fixtures/.gitkeep`

- [ ] **Step 4: Build and run**

Run: `cd SnapBackApp && swift test`
Expected: one test runs and passes (`testHarnessBuilds`). Swift 5.9 + macOS 13 must be available.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Package.swift SnapBackApp/Tests
git commit -m "chore(bridge): add BridgeTests XCTest target with smoke harness"
```

---

## Phase 5 — Protocol codec and shared test vectors

### Task 5.1: Define `ProtocolMessage` type and direction (TDD)

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift`
- Create: `SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import SnapBackApp

final class MessageCodecTypesTests: XCTestCase {
    func testMessageTypeExists() {
        let message = ProtocolMessage(
            version: 1,
            type: .attention,
            timestamp: 1_734_556_677,
            nonceHex: String(repeating: "a", count: 32),
            payload: ["hook": .string("PermissionRequest")]
        )
        XCTAssertEqual(message.version, 1)
        XCTAssertEqual(message.type, .attention)
    }

    func testDirectionEnumCoversBothSides() {
        XCTAssertEqual(ProtocolDirection.clientToServer.rawValue, "c2s")
        XCTAssertEqual(ProtocolDirection.serverToClient.rawValue, "s2c")
    }
}
```

- [ ] **Step 2: Run and confirm fail**

Run: `cd SnapBackApp && swift test`
Expected: compilation error — `ProtocolMessage`, `ProtocolDirection`, `ProtocolMessageType`, and `JSONValue` do not exist.

- [ ] **Step 3: Create `MessageCodec.swift` with the minimum types to satisfy the test**

```swift
import Foundation

/// Direction of a signed message on the wire. Used as the first segment of the HMAC domain.
public enum ProtocolDirection: String {
    case clientToServer = "c2s"
    case serverToClient = "s2c"
}

/// The fixed set of message types in protocol v1.
public enum ProtocolMessageType: String, CaseIterable {
    case hello
    case ack
    case attention
    case resume
    case heartbeat
    case pong
    case resync
    case invalidate
}

/// A canonical, serializable JSON value type.
/// Using a bespoke enum (rather than `Any`) guarantees deterministic serialization.
public indirect enum JSONValue: Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([(String, JSONValue)]) // ordered; canonical serializer sorts by key
}

/// A protocol v1 message, language-agnostic shape.
public struct ProtocolMessage: Equatable {
    public var version: Int
    public var type: ProtocolMessageType
    public var timestamp: Int64
    public var nonceHex: String                // exactly 32 lowercase hex chars
    public var payload: [(String, JSONValue)]  // may be empty

    public init(version: Int,
                type: ProtocolMessageType,
                timestamp: Int64,
                nonceHex: String,
                payload: [(String, JSONValue)] = []) {
        self.version = version
        self.type = type
        self.timestamp = timestamp
        self.nonceHex = nonceHex
        self.payload = payload
    }

    public static func == (lhs: ProtocolMessage, rhs: ProtocolMessage) -> Bool {
        lhs.version == rhs.version &&
        lhs.type == rhs.type &&
        lhs.timestamp == rhs.timestamp &&
        lhs.nonceHex == rhs.nonceHex &&
        lhs.payload.map { $0.0 } == rhs.payload.map { $0.0 } &&
        lhs.payload.map { $0.1 } == rhs.payload.map { $0.1 }
    }
}
```

- [ ] **Step 4: Run the test**

Run: `cd SnapBackApp && swift test`
Expected: both type tests pass.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift
git commit -m "feat(bridge): scaffold ProtocolMessage / ProtocolDirection / JSONValue types"
```

### Task 5.2: Canonical JSON serialization (TDD)

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift`
- Modify: `SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift`

- [ ] **Step 1: Append the failing test**

```swift
final class CanonicalJSONTests: XCTestCase {
    func testObjectKeysSortedAlphabetically() {
        let payload: [(String, JSONValue)] = [
            ("b", .int(2)),
            ("a", .int(1))
        ]
        let bytes = CanonicalJSON.encode(.object(payload))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "{\"a\":1,\"b\":2}")
    }

    func testEmptyObject() {
        let bytes = CanonicalJSON.encode(.object([]))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "{}")
    }

    func testEscaping() {
        let bytes = CanonicalJSON.encode(.string("a\"b\\c\n"))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "\"a\\\"b\\\\c\\n\"")
    }

    func testIntegersNoFraction() {
        let bytes = CanonicalJSON.encode(.int(0))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "0")
    }

    func testBooleansAndNull() {
        XCTAssertEqual(String(data: CanonicalJSON.encode(.bool(true)),  encoding: .utf8), "true")
        XCTAssertEqual(String(data: CanonicalJSON.encode(.bool(false)), encoding: .utf8), "false")
        XCTAssertEqual(String(data: CanonicalJSON.encode(.null),        encoding: .utf8), "null")
    }
}
```

- [ ] **Step 2: Run, confirm fail (no `CanonicalJSON` yet)**

Run: `cd SnapBackApp && swift test`
Expected: compile error.

- [ ] **Step 3: Append to `MessageCodec.swift`**

```swift
/// Deterministic JSON encoder. The spec's HMAC domain (§4.1) requires byte-for-byte
/// reproducibility across implementations. This encoder therefore:
///   • sorts object keys (lexicographic on the UTF-8 bytes)
///   • emits integers as shortest decimal
///   • emits doubles with the minimum representation that round-trips
///   • escapes strings with only the six required backslash escapes and \uXXXX for
///     control chars
///   • emits no whitespace
public enum CanonicalJSON {
    public static func encode(_ value: JSONValue) -> Data {
        var out = Data()
        append(value, to: &out)
        return out
    }

    private static func append(_ value: JSONValue, to out: inout Data) {
        switch value {
        case .null:
            out.append(contentsOf: "null".utf8)
        case .bool(let b):
            out.append(contentsOf: (b ? "true" : "false").utf8)
        case .int(let i):
            out.append(contentsOf: String(i).utf8)
        case .double(let d):
            // Use Swift's default repr which is the shortest round-trip.
            out.append(contentsOf: String(d).utf8)
        case .string(let s):
            appendString(s, to: &out)
        case .array(let arr):
            out.append(UInt8(ascii: "["))
            for (idx, v) in arr.enumerated() {
                if idx > 0 { out.append(UInt8(ascii: ",")) }
                append(v, to: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let pairs):
            let sorted = pairs.sorted { $0.0 < $1.0 }
            out.append(UInt8(ascii: "{"))
            for (idx, kv) in sorted.enumerated() {
                if idx > 0 { out.append(UInt8(ascii: ",")) }
                appendString(kv.0, to: &out)
                out.append(UInt8(ascii: ":"))
                append(kv.1, to: &out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    private static func appendString(_ s: String, to out: inout Data) {
        out.append(UInt8(ascii: "\""))
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out.append(contentsOf: "\\\"".utf8)
            case "\\": out.append(contentsOf: "\\\\".utf8)
            case "\u{08}": out.append(contentsOf: "\\b".utf8)
            case "\u{09}": out.append(contentsOf: "\\t".utf8)
            case "\u{0A}": out.append(contentsOf: "\\n".utf8)
            case "\u{0C}": out.append(contentsOf: "\\f".utf8)
            case "\u{0D}": out.append(contentsOf: "\\r".utf8)
            default:
                if scalar.value < 0x20 {
                    out.append(contentsOf: String(format: "\\u%04x", scalar.value).utf8)
                } else {
                    out.append(contentsOf: String(scalar).utf8)
                }
            }
        }
        out.append(UInt8(ascii: "\""))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: all five `CanonicalJSONTests` cases pass.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift
git commit -m "feat(bridge): deterministic canonical JSON encoder"
```

### Task 5.3: HMAC signing domain (TDD)

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift`
- Modify: `SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift`

- [ ] **Step 1: Append failing tests**

```swift
final class SigningDomainTests: XCTestCase {
    func testDomainHasDirectionFirstAndNullSeparators() {
        let msg = ProtocolMessage(
            version: 1,
            type: .attention,
            timestamp: 1_734_556_677,
            nonceHex: String(repeating: "0", count: 32),
            payload: [("hook", .string("Stop"))]
        )
        let domain = MessageCodec.signingDomain(for: msg, direction: .clientToServer)
        let expected: [UInt8] = Array(
            ("c2s\u{00}1\u{00}attention\u{00}1734556677\u{00}" +
             String(repeating: "0", count: 32) + "\u{00}" +
             "{\"hook\":\"Stop\"}").utf8
        )
        XCTAssertEqual(Array(domain), expected)
    }

    func testEmptyPayloadSerializesAsOpenClose() {
        let msg = ProtocolMessage(
            version: 1,
            type: .resume,
            timestamp: 100,
            nonceHex: String(repeating: "1", count: 32),
            payload: []
        )
        let domain = MessageCodec.signingDomain(for: msg, direction: .clientToServer)
        let domainStr = String(data: domain, encoding: .utf8)
        XCTAssertEqual(domainStr?.hasSuffix("\u{00}{}"), true)
    }
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `cd SnapBackApp && swift test`

- [ ] **Step 3: Append to `MessageCodec.swift`**

```swift
public enum MessageCodec {
    /// Returns the exact bytes fed into HMAC-SHA256. See spec §4.1 signing domain.
    public static func signingDomain(for message: ProtocolMessage,
                                     direction: ProtocolDirection) -> Data {
        var out = Data()
        out.append(contentsOf: direction.rawValue.utf8)
        out.append(0x00)
        out.append(contentsOf: String(message.version).utf8)
        out.append(0x00)
        out.append(contentsOf: message.type.rawValue.utf8)
        out.append(0x00)
        out.append(contentsOf: String(message.timestamp).utf8)
        out.append(0x00)
        out.append(contentsOf: message.nonceHex.utf8)
        out.append(0x00)
        out.append(CanonicalJSON.encode(.object(message.payload)))
        return out
    }
}
```

- [ ] **Step 4: Run**

Run: `cd SnapBackApp && swift test`
Expected: the two `SigningDomainTests` cases pass.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift
git commit -m "feat(bridge): deterministic HMAC signing domain with direction byte"
```

### Task 5.4: HMAC sign + verify (TDD, using `CryptoKit`)

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift`
- Modify: `SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift`

- [ ] **Step 1: Append failing tests**

```swift
final class HMACSignVerifyTests: XCTestCase {
    private let secret = Data(repeating: 0x42, count: 32)

    func testSignProducesLowercaseHexOfConstantLength() {
        let msg = ProtocolMessage(
            version: 1, type: .heartbeat, timestamp: 1, nonceHex: String(repeating: "0", count: 32)
        )
        let sig = MessageCodec.sign(message: msg, direction: .clientToServer, secret: secret)
        XCTAssertEqual(sig.count, 64)
        XCTAssertTrue(sig.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testVerifyAcceptsCorrectSignature() {
        let msg = ProtocolMessage(
            version: 1, type: .hello, timestamp: 17, nonceHex: String(repeating: "0", count: 32)
        )
        let sig = MessageCodec.sign(message: msg, direction: .clientToServer, secret: secret)
        XCTAssertTrue(
            MessageCodec.verify(message: msg, direction: .clientToServer, hmacHex: sig, secret: secret)
        )
    }

    func testVerifyRejectsOnDirectionMismatch() {
        let msg = ProtocolMessage(
            version: 1, type: .hello, timestamp: 17, nonceHex: String(repeating: "0", count: 32)
        )
        let sig = MessageCodec.sign(message: msg, direction: .clientToServer, secret: secret)
        XCTAssertFalse(
            MessageCodec.verify(message: msg, direction: .serverToClient, hmacHex: sig, secret: secret)
        )
    }

    func testVerifyRejectsOnTamperedField() {
        var msg = ProtocolMessage(
            version: 1, type: .attention, timestamp: 17, nonceHex: String(repeating: "0", count: 32)
        )
        let sig = MessageCodec.sign(message: msg, direction: .clientToServer, secret: secret)
        msg.timestamp = 18
        XCTAssertFalse(
            MessageCodec.verify(message: msg, direction: .clientToServer, hmacHex: sig, secret: secret)
        )
    }
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `cd SnapBackApp && swift test`

- [ ] **Step 3: Extend `MessageCodec` with signing functions**

Add at the top of `MessageCodec.swift`:

```swift
import CryptoKit
```

Append inside `MessageCodec`:

```swift
    public static func sign(message: ProtocolMessage,
                            direction: ProtocolDirection,
                            secret: Data) -> String {
        let domain = signingDomain(for: message, direction: direction)
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: domain, using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(message: ProtocolMessage,
                              direction: ProtocolDirection,
                              hmacHex: String,
                              secret: Data) -> Bool {
        guard let expected = Data(hex: hmacHex) else { return false }
        let domain = signingDomain(for: message, direction: direction)
        let key = SymmetricKey(data: secret)
        let actual = Data(HMAC<SHA256>.authenticationCode(for: domain, using: key))
        guard expected.count == actual.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<actual.count { diff |= expected[i] ^ actual[i] }
        return diff == 0
    }
```

Append at file scope:

```swift
private extension Data {
    init?(hex: String) {
        let clean = hex.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard clean.count % 2 == 0 else { return nil }
        var buf = Data(capacity: clean.count / 2)
        var i = clean.startIndex
        while i < clean.endIndex {
            let hi = clean[i]
            let lo = clean[clean.index(after: i)]
            guard let byte = UInt8(String(hi) + String(lo), radix: 16) else { return nil }
            buf.append(byte)
            i = clean.index(i, offsetBy: 2)
        }
        self = buf
    }
}
```

- [ ] **Step 4: Run**

Run: `cd SnapBackApp && swift test`
Expected: four HMAC cases pass.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift
git commit -m "feat(bridge): HMAC-SHA256 sign and constant-time verify using CryptoKit"
```

### Task 5.5: JSON wire encode/decode of a signed message (TDD)

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift`
- Modify: `SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift`

- [ ] **Step 1: Append failing test**

```swift
final class WireEncodeDecodeTests: XCTestCase {
    private let secret = Data(repeating: 0xAB, count: 32)

    func testRoundTripSignedMessage() throws {
        let original = ProtocolMessage(
            version: 1,
            type: .attention,
            timestamp: 1_734_556_677,
            nonceHex: String(repeating: "a", count: 32),
            payload: [("hook", .string("PermissionRequest"))]
        )
        let line = try MessageCodec.encodeSignedLine(
            original, direction: .clientToServer, secret: secret
        )
        XCTAssertTrue(line.hasSuffix("\n"))

        let (decoded, hmac) = try MessageCodec.decodeLine(line)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(
            MessageCodec.verify(message: decoded, direction: .clientToServer,
                                hmacHex: hmac, secret: secret)
        )
    }

    func testDecodeRejectsMissingHmac() {
        let json = "{\"v\":1,\"type\":\"resume\",\"ts\":1,\"nonce\":\"" +
                   String(repeating: "0", count: 32) + "\",\"payload\":{}}\n"
        XCTAssertThrowsError(try MessageCodec.decodeLine(json))
    }

    func testDecodeRejectsUnknownType() {
        let json = "{\"v\":1,\"type\":\"bogus\",\"ts\":1,\"nonce\":\"" +
                   String(repeating: "0", count: 32) + "\",\"payload\":{},\"hmac\":\"x\"}\n"
        XCTAssertThrowsError(try MessageCodec.decodeLine(json))
    }
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `cd SnapBackApp && swift test`

- [ ] **Step 3: Append to `MessageCodec.swift`**

```swift
public enum MessageCodecError: Error {
    case invalidJSON
    case missingField(String)
    case unknownType(String)
    case invalidNonce
    case invalidPayload
}

extension MessageCodec {
    /// Encode `message` as a complete wire line (JSON + trailing `\n`), signed in `direction`.
    public static func encodeSignedLine(_ message: ProtocolMessage,
                                        direction: ProtocolDirection,
                                        secret: Data) throws -> String {
        let hmac = sign(message: message, direction: direction, secret: secret)
        var body: [(String, JSONValue)] = [
            ("hmac", .string(hmac)),
            ("nonce", .string(message.nonceHex)),
            ("payload", .object(message.payload)),
            ("ts", .int(message.timestamp)),
            ("type", .string(message.type.rawValue)),
            ("v", .int(Int64(message.version)))
        ]
        body.sort { $0.0 < $1.0 }
        let data = CanonicalJSON.encode(.object(body))
        guard var s = String(data: data, encoding: .utf8) else { throw MessageCodecError.invalidJSON }
        s.append("\n")
        return s
    }

    /// Decode a wire line into `(message, hmac_hex)`. Verification is the caller's job.
    public static func decodeLine(_ line: String) throws -> (ProtocolMessage, String) {
        let trimmed = line.hasSuffix("\n") ? String(line.dropLast()) : line
        guard let data = trimmed.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: []),
              let obj = any as? [String: Any] else {
            throw MessageCodecError.invalidJSON
        }
        guard let v = obj["v"] as? Int else { throw MessageCodecError.missingField("v") }
        guard let typeString = obj["type"] as? String else { throw MessageCodecError.missingField("type") }
        guard let type = ProtocolMessageType(rawValue: typeString) else {
            throw MessageCodecError.unknownType(typeString)
        }
        guard let ts = obj["ts"] as? Int64 ?? (obj["ts"] as? Int).map(Int64.init) else {
            throw MessageCodecError.missingField("ts")
        }
        guard let nonce = obj["nonce"] as? String, nonce.count == 32 else {
            throw MessageCodecError.invalidNonce
        }
        guard let hmac = obj["hmac"] as? String else { throw MessageCodecError.missingField("hmac") }
        let payloadAny = obj["payload"] ?? [String: Any]()
        guard let payloadDict = payloadAny as? [String: Any] else {
            throw MessageCodecError.invalidPayload
        }
        let payload: [(String, JSONValue)] = try payloadDict
            .sorted { $0.key < $1.key }
            .map { (k, v) in (k, try JSONValue.fromAny(v)) }

        let msg = ProtocolMessage(version: v, type: type, timestamp: ts,
                                  nonceHex: nonce, payload: payload)
        return (msg, hmac)
    }
}

extension JSONValue {
    static func fromAny(_ any: Any) throws -> JSONValue {
        if let s = any as? String { return .string(s) }
        if let i = any as? Int64 { return .int(i) }
        if let i = any as? Int { return .int(Int64(i)) }
        if let d = any as? Double { return .double(d) }
        if let b = any as? Bool { return .bool(b) }
        if any is NSNull { return .null }
        if let arr = any as? [Any] {
            return .array(try arr.map { try JSONValue.fromAny($0) })
        }
        if let obj = any as? [String: Any] {
            let pairs = try obj.sorted { $0.key < $1.key }
                               .map { ($0.key, try JSONValue.fromAny($0.value)) }
            return .object(pairs)
        }
        throw MessageCodecError.invalidPayload
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: three tests in `WireEncodeDecodeTests` pass.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift SnapBackApp/Tests/BridgeTests/MessageCodecTests.swift
git commit -m "feat(bridge): wire encode/decode of signed protocol messages"
```

### Task 5.6: Shared protocol vectors fixture (TDD)

**Files:**
- Create: `tests/protocol-vectors.json`
- Create: `SnapBackApp/Tests/BridgeTests/fixtures/protocol-vectors.json` (symlink or copy)
- Create: `SnapBackApp/Tests/BridgeTests/ProtocolVectorsTests.swift`

- [ ] **Step 1: Write `tests/protocol-vectors.json`**

```json
{
  "v": 1,
  "secret_hex": "4242424242424242424242424242424242424242424242424242424242424242",
  "vectors": [
    {
      "name": "attention_permission_request",
      "direction": "c2s",
      "message": {
        "v": 1,
        "type": "attention",
        "ts": 1734556677,
        "nonce": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "payload": { "hook": "PermissionRequest" }
      }
    },
    {
      "name": "resume_empty_payload",
      "direction": "c2s",
      "message": {
        "v": 1,
        "type": "resume",
        "ts": 1734556800,
        "nonce": "00000000000000000000000000000000",
        "payload": {}
      }
    },
    {
      "name": "pong_with_hold_state",
      "direction": "s2c",
      "message": {
        "v": 1,
        "type": "pong",
        "ts": 1734557000,
        "nonce": "ffffffffffffffffffffffffffffffff",
        "payload": { "hold": true }
      }
    }
  ]
}
```

*(Signatures are computed and filled in by the test itself in the first run — see Step 2.)*

- [ ] **Step 2: Point the Swift test target at the fixture**

Run: `cp tests/protocol-vectors.json SnapBackApp/Tests/BridgeTests/fixtures/protocol-vectors.json`

(Keep the root copy canonical; the Swift test target's copy is the one bundled as a resource. Task 14.x will add a commit hook to keep them in sync.)

- [ ] **Step 3: Write `ProtocolVectorsTests.swift` that reads the fixture and asserts sign/verify round-trip**

```swift
import XCTest
@testable import SnapBackApp

final class ProtocolVectorsTests: XCTestCase {
    struct Fixture: Decodable {
        let v: Int
        let secret_hex: String
        let vectors: [Vector]

        struct Vector: Decodable {
            let name: String
            let direction: String
            let message: MessageBody
        }
        struct MessageBody: Decodable {
            let v: Int
            let type: String
            let ts: Int64
            let nonce: String
            let payload: [String: JSONAny]
        }
    }

    // Loose JSON-any decoder for fixture payloads (unit test only).
    struct JSONAny: Decodable {
        let raw: Any
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { raw = s; return }
            if let i = try? c.decode(Int64.self)  { raw = i; return }
            if let d = try? c.decode(Double.self) { raw = d; return }
            if let b = try? c.decode(Bool.self)   { raw = b; return }
            if c.decodeNil()                      { raw = NSNull(); return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported")
        }
    }

    func testAllVectorsRoundTrip() throws {
        let url = Bundle.module.url(forResource: "protocol-vectors", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let fx = try JSONDecoder().decode(Fixture.self, from: data)
        let secret = Data(hex: fx.secret_hex)!

        for v in fx.vectors {
            let payload = v.message.payload
                .sorted { $0.key < $1.key }
                .map { ($0.key, try! JSONValue.fromAny($0.value.raw)) }
            let direction = ProtocolDirection(rawValue: v.direction)!
            let type = ProtocolMessageType(rawValue: v.message.type)!
            let msg = ProtocolMessage(
                version: v.message.v,
                type: type,
                timestamp: v.message.ts,
                nonceHex: v.message.nonce,
                payload: payload
            )
            let line = try MessageCodec.encodeSignedLine(msg, direction: direction, secret: secret)
            let (decoded, hmac) = try MessageCodec.decodeLine(line)
            XCTAssertEqual(decoded, msg, "\(v.name) round-trip mismatch")
            XCTAssertTrue(
                MessageCodec.verify(message: decoded, direction: direction, hmacHex: hmac, secret: secret),
                "\(v.name) verify failed"
            )
        }
    }
}

// Expose the private `Data(hex:)` initializer for the test.
extension Data {
    static func hex(_ s: String) -> Data? { Data(hex: s) }
}
```

*(The internal `Data(hex:)` is `fileprivate` in `MessageCodec.swift`. Make it `internal` by removing the `private` access modifier on that extension so the test target can use it via `@testable import SnapBackApp`.)*

- [ ] **Step 4: Bump access on the hex extension in `MessageCodec.swift`**

Change:
```swift
private extension Data {
    init?(hex: String) {
```
to:
```swift
extension Data {
    init?(hex: String) {
```

- [ ] **Step 5: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: `testAllVectorsRoundTrip` passes for all three vectors.

- [ ] **Step 6: Commit**

```bash
git add tests/protocol-vectors.json SnapBackApp/Tests/BridgeTests/fixtures/protocol-vectors.json SnapBackApp/Tests/BridgeTests/ProtocolVectorsTests.swift SnapBackApp/Sources/SnapBackApp/Bridge/MessageCodec.swift
git commit -m "test(bridge): shared protocol vectors fixture (Swift round-trip)"
```

---

## Phase 6 — NonceCache (TDD)

### Task 6.1: LRU + TTL nonce cache

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/NonceCache.swift`
- Create: `SnapBackApp/Tests/BridgeTests/NonceCacheTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import SnapBackApp

final class NonceCacheTests: XCTestCase {
    func testAcceptsFirstOccurrence() {
        let cache = NonceCache(capacity: 8, ttlSeconds: 600)
        XCTAssertTrue(cache.tryAdd("n1", at: 100))
    }

    func testRejectsDuplicateWithinTTL() {
        let cache = NonceCache(capacity: 8, ttlSeconds: 600)
        _ = cache.tryAdd("n1", at: 100)
        XCTAssertFalse(cache.tryAdd("n1", at: 101))
    }

    func testAcceptsAfterTTL() {
        let cache = NonceCache(capacity: 8, ttlSeconds: 600)
        _ = cache.tryAdd("n1", at: 100)
        XCTAssertTrue(cache.tryAdd("n1", at: 701))
    }

    func testEvictsOldestWhenOverCapacity() {
        let cache = NonceCache(capacity: 2, ttlSeconds: 600)
        _ = cache.tryAdd("a", at: 100)
        _ = cache.tryAdd("b", at: 101)
        _ = cache.tryAdd("c", at: 102)
        // "a" should be gone, so re-adding it is accepted.
        XCTAssertTrue(cache.tryAdd("a", at: 103))
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `NonceCache.swift`**

```swift
import Foundation

/// Bounded TTL+LRU cache for replay protection.
/// Thread-safe via an internal serial queue.
public final class NonceCache {
    private let capacity: Int
    private let ttl: TimeInterval
    private var entries: [(nonce: String, insertedAt: TimeInterval)] = []
    private let queue = DispatchQueue(label: "com.snapback.bridge.nonceCache")

    public init(capacity: Int, ttlSeconds: TimeInterval) {
        self.capacity = capacity
        self.ttl = ttlSeconds
    }

    /// Returns `true` if the nonce was new and has now been recorded.
    /// `now` is expressed in unix seconds; the caller supplies it so tests are deterministic.
    public func tryAdd(_ nonce: String, at now: TimeInterval) -> Bool {
        queue.sync {
            entries.removeAll { now - $0.insertedAt > ttl }
            if entries.contains(where: { $0.nonce == nonce }) { return false }
            entries.append((nonce: nonce, insertedAt: now))
            while entries.count > capacity { entries.removeFirst() }
            return true
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: all four `NonceCacheTests` pass.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/NonceCache.swift SnapBackApp/Tests/BridgeTests/NonceCacheTests.swift
git commit -m "feat(bridge): thread-safe NonceCache (LRU+TTL) for replay protection"
```

---

## Phase 7 — Keychain token store (TDD)

### Task 7.1: `KeychainTokenStore` — generate / read / delete

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/KeychainTokenStore.swift`
- Create: `SnapBackApp/Tests/BridgeTests/KeychainTokenStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import SnapBackApp

final class KeychainTokenStoreTests: XCTestCase {
    // Use a service name unique to the test run so parallel runs don't collide
    // and so no production token is touched.
    private func testStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "com.snapback.mobile.test.\(UUID().uuidString)",
                           account: "pair-token")
    }

    func testReadReturnsNilWhenAbsent() {
        let store = testStore()
        XCTAssertNil(store.read())
    }

    func testGenerateAndReadRoundTrip() throws {
        let store = testStore()
        defer { try? store.delete() }
        let token = try store.generateAndStore()
        XCTAssertEqual(token.count, 32)
        let read = store.read()
        XCTAssertEqual(read, token)
    }

    func testDeleteRemovesEntry() throws {
        let store = testStore()
        _ = try store.generateAndStore()
        try store.delete()
        XCTAssertNil(store.read())
    }
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `cd SnapBackApp && swift test`
Expected: compile fails — `KeychainTokenStore` missing.

- [ ] **Step 3: Create `KeychainTokenStore.swift`**

```swift
import Foundation
import Security

public enum KeychainTokenStoreError: Error {
    case osStatus(OSStatus)
    case rngFailed
    case malformedExistingItem
}

/// Minimal wrapper around the macOS Keychain for the pair token.
/// Uses kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so the secret does NOT
/// sync via iCloud Keychain.
public final class KeychainTokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.snapback.mobile",
                account: String = "pair-token") {
        self.service = service
        self.account = account
    }

    public func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    public func generateAndStore() throws -> Data {
        try delete() // idempotent

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeychainTokenStoreError.rngFailed }
        let token = Data(bytes)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: token
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainTokenStoreError.osStatus(addStatus)
        }
        return token
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainTokenStoreError.osStatus(status)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: all three `KeychainTokenStoreTests` pass. **Note:** first run may prompt for Keychain permission in a GUI dialog — click "Always Allow" for the test runner binary.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/KeychainTokenStore.swift SnapBackApp/Tests/BridgeTests/KeychainTokenStoreTests.swift
git commit -m "feat(bridge): KeychainTokenStore (ThisDeviceOnly, no iCloud sync)"
```

---

## Phase 8 — Event queue with retry/backoff (TDD)

### Task 8.1: `EventQueue`

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/EventQueue.swift`
- Create: `SnapBackApp/Tests/BridgeTests/EventQueueTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import SnapBackApp

final class EventQueueTests: XCTestCase {
    func testEnqueueDequeueFIFO() {
        let q = EventQueue(capacity: 4)
        q.enqueue(.attention(kind: "Stop"))
        q.enqueue(.resume)
        XCTAssertEqual(q.depth, 2)
        XCTAssertEqual(q.pop(), BridgeEvent.attention(kind: "Stop"))
        XCTAssertEqual(q.pop(), .resume)
        XCTAssertNil(q.pop())
    }

    func testBoundedCapacityDropsOldest() {
        let q = EventQueue(capacity: 2)
        q.enqueue(.attention(kind: "A"))
        q.enqueue(.attention(kind: "B"))
        q.enqueue(.attention(kind: "C"))
        XCTAssertEqual(q.depth, 2)
        XCTAssertEqual(q.pop(), .attention(kind: "B"))
        XCTAssertEqual(q.pop(), .attention(kind: "C"))
    }

    func testBackoffSchedule() {
        XCTAssertEqual(RetryPolicy.nextDelay(attemptsSoFar: 0), 0.5)
        XCTAssertEqual(RetryPolicy.nextDelay(attemptsSoFar: 1), 2.0)
        XCTAssertEqual(RetryPolicy.nextDelay(attemptsSoFar: 2), 8.0)
        XCTAssertNil(RetryPolicy.nextDelay(attemptsSoFar: 3))
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `EventQueue.swift`**

```swift
import Foundation

public enum BridgeEvent: Equatable {
    case attention(kind: String)   // "PermissionRequest" | "Stop"
    case resume
}

public enum RetryPolicy {
    public static func nextDelay(attemptsSoFar: Int) -> TimeInterval? {
        switch attemptsSoFar {
        case 0: return 0.5
        case 1: return 2.0
        case 2: return 8.0
        default: return nil
        }
    }
}

public final class EventQueue {
    private let capacity: Int
    private var buffer: [BridgeEvent] = []
    private let queue = DispatchQueue(label: "com.snapback.bridge.eventQueue")

    public init(capacity: Int = 16) { self.capacity = capacity }

    public var depth: Int { queue.sync { buffer.count } }

    public func enqueue(_ event: BridgeEvent) {
        queue.sync {
            buffer.append(event)
            while buffer.count > capacity { buffer.removeFirst() }
        }
    }

    public func pop() -> BridgeEvent? {
        queue.sync { buffer.isEmpty ? nil : buffer.removeFirst() }
    }

    public func peek() -> BridgeEvent? {
        queue.sync { buffer.first }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/EventQueue.swift SnapBackApp/Tests/BridgeTests/EventQueueTests.swift
git commit -m "feat(bridge): bounded EventQueue + backoff schedule"
```

---

## Phase 9 — `BridgeStatus` and log

### Task 9.1: `BridgeStatus` enum + `ObservableObject` publisher

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeStatus.swift`
- Create: `SnapBackApp/Tests/BridgeTests/BridgeStatusTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import Combine
@testable import SnapBackApp

final class BridgeStatusTests: XCTestCase {
    func testInitialStatusIsUnpaired() {
        let s = BridgeStatusPublisher()
        XCTAssertEqual(s.current, .unpaired)
    }

    func testUpdatePropagates() {
        let s = BridgeStatusPublisher()
        let exp = expectation(description: "status update")
        var cancellables = Set<AnyCancellable>()
        s.$current
          .dropFirst() // skip initial value
          .sink { status in
              if status == .connected { exp.fulfill() }
          }
          .store(in: &cancellables)
        s.update(.connected)
        wait(for: [exp], timeout: 1.0)
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `BridgeStatus.swift`**

```swift
import Foundation
import Combine

public enum BridgeStatus: Equatable {
    case unpaired
    case connecting
    case connected
    case unreachable
    case error(String)
}

public final class BridgeStatusPublisher: ObservableObject {
    @Published public private(set) var current: BridgeStatus = .unpaired

    public init() {}

    public func update(_ new: BridgeStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.current != new { self.current = new }
        }
    }
}
```

- [ ] **Step 4: Run tests**

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/BridgeStatus.swift SnapBackApp/Tests/BridgeTests/BridgeStatusTests.swift
git commit -m "feat(bridge): BridgeStatus enum with Combine publisher"
```

### Task 9.2: `BridgeLog` — rolling file log

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeLog.swift`
- Create: `SnapBackApp/Tests/BridgeTests/BridgeLogTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import SnapBackApp

final class BridgeLogTests: XCTestCase {
    var tmpDir: URL!

    override func setUp() {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snapback-log-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testWritesToFile() throws {
        let log = BridgeLog(directory: tmpDir, basename: "bridge.log",
                            maxBytes: 1024, rotations: 2)
        log.info("hello world")
        log.flush()
        let url = tmpDir.appendingPathComponent("bridge.log")
        let contents = try String(contentsOf: url)
        XCTAssertTrue(contents.contains("hello world"))
    }

    func testRotatesAfterMaxBytes() throws {
        let log = BridgeLog(directory: tmpDir, basename: "bridge.log",
                            maxBytes: 100, rotations: 2)
        for i in 0..<50 { log.info("line \(i) with some padding xxxxxxxxxxxxxx") }
        log.flush()
        let base = tmpDir.appendingPathComponent("bridge.log")
        let rotated = tmpDir.appendingPathComponent("bridge.log.1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: base.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `BridgeLog.swift`**

```swift
import Foundation

public final class BridgeLog {
    private let directory: URL
    private let basename: String
    private let maxBytes: Int
    private let rotations: Int
    private let queue = DispatchQueue(label: "com.snapback.bridge.log")
    private var handle: FileHandle?
    private let formatter: DateFormatter

    public init(directory: URL,
                basename: String = "bridge.log",
                maxBytes: Int = 1_048_576,
                rotations: Int = 5) {
        self.directory = directory
        self.basename = basename
        self.maxBytes = maxBytes
        self.rotations = rotations
        self.formatter = DateFormatter()
        self.formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.formatter.locale = Locale(identifier: "en_US_POSIX")
    }

    public func info(_ message: String) { write("INFO", message) }
    public func warn(_ message: String) { write("WARN", message) }
    public func error(_ message: String) { write("ERROR", message) }

    private func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        queue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let url = self.directory.appendingPathComponent(self.basename)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            if self.handle == nil {
                self.handle = try? FileHandle(forWritingTo: url)
                try? self.handle?.seekToEnd()
            }
            self.handle?.write(Data(line.utf8))
            self.rotateIfNeeded(url: url)
        }
    }

    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    private func rotateIfNeeded(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size >= maxBytes else { return }
        handle?.closeFile()
        handle = nil
        for i in stride(from: rotations - 1, through: 1, by: -1) {
            let src = directory.appendingPathComponent("\(basename).\(i)")
            let dst = directory.appendingPathComponent("\(basename).\(i+1)")
            _ = try? FileManager.default.removeItem(at: dst)
            _ = try? FileManager.default.moveItem(at: src, to: dst)
        }
        let firstRotation = directory.appendingPathComponent("\(basename).1")
        _ = try? FileManager.default.removeItem(at: firstRotation)
        _ = try? FileManager.default.moveItem(at: url, to: firstRotation)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        try? handle?.seekToEnd()
    }
}
```

- [ ] **Step 4: Run tests**

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/BridgeLog.swift SnapBackApp/Tests/BridgeTests/BridgeLogTests.swift
git commit -m "feat(bridge): rolling BridgeLog writer"
```

---

## Phase 10 — `BridgeServer` (UDS listener)

### Task 10.1: Parse incoming TSV-ish lines into `BridgeEvent`s

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeServer.swift`
- Create: `SnapBackApp/Tests/BridgeTests/BridgeServerTests.swift`

- [ ] **Step 1: Write failing test for the pure parser (no IO)**

```swift
import XCTest
@testable import SnapBackApp

final class BridgeServerParserTests: XCTestCase {
    func testParsesAttentionWithKind() {
        let ev = BridgeServer.parseLine("attention\tStop")
        XCTAssertEqual(ev, .attention(kind: "Stop"))
    }

    func testParsesAttentionWithoutKind() {
        let ev = BridgeServer.parseLine("attention")
        XCTAssertEqual(ev, .attention(kind: "Stop"))
    }

    func testParsesResume() {
        let ev = BridgeServer.parseLine("resume")
        XCTAssertEqual(ev, .resume)
    }

    func testReturnsNilForUnknown() {
        XCTAssertNil(BridgeServer.parseLine("bogus"))
        XCTAssertNil(BridgeServer.parseLine(""))
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `BridgeServer.swift` (parser only for now)**

```swift
import Foundation
import Network

public final class BridgeServer {
    public static func parseLine(_ raw: String) -> BridgeEvent? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return nil }
        let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        switch parts[0] {
        case "attention":
            let kind = parts.count > 1 ? String(parts[1]) : "Stop"
            return .attention(kind: kind)
        case "resume":
            return .resume
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run, confirm pass**

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/BridgeServer.swift SnapBackApp/Tests/BridgeTests/BridgeServerTests.swift
git commit -m "feat(bridge): BridgeServer line parser"
```

### Task 10.2: Unix-domain listener that drains into the event queue

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeServer.swift`
- Modify: `SnapBackApp/Tests/BridgeTests/BridgeServerTests.swift`

- [ ] **Step 1: Append an integration-style test that starts the listener and pokes it**

```swift
final class BridgeServerIntegrationTests: XCTestCase {
    func testListenerReceivesEventsFromPoke() throws {
        let sockPath = NSTemporaryDirectory() + "snapback-bridge-test-\(UUID().uuidString).sock"
        defer { try? FileManager.default.removeItem(atPath: sockPath) }
        let queue = EventQueue()
        let server = BridgeServer(socketPath: sockPath, eventQueue: queue,
                                  log: BridgeLog(directory: URL(fileURLWithPath: NSTemporaryDirectory())))
        try server.start()
        defer { server.stop() }

        // Wait for the socket to appear.
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: sockPath) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Write "attention\tPermissionRequest\n" over AF_UNIX.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThan(fd, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        sockPath.withCString { ptr in
            _ = withUnsafeMutableBytes(of: &addr.sun_path) { buf in
                buf.baseAddress!.copyMemory(from: UnsafeRawPointer(ptr), byteCount: strlen(ptr))
            }
        }
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connectResult, 0)
        let msg = "attention\tPermissionRequest\n"
        _ = msg.withCString { write(fd, $0, strlen($0)) }
        shutdown(fd, SHUT_WR)
        close(fd)

        // Poll for up to 1 s.
        for _ in 0..<20 {
            if queue.depth >= 1 { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(queue.depth, 1)
        XCTAssertEqual(queue.pop(), .attention(kind: "PermissionRequest"))
    }
}
```

- [ ] **Step 2: Run, confirm fail (no initializer yet)**

- [ ] **Step 3: Extend `BridgeServer.swift`**

Add on `BridgeServer`:

```swift
    private let socketPath: String
    private let eventQueue: EventQueue
    private let log: BridgeLog
    private var listener: NWListener?

    public init(socketPath: String,
                eventQueue: EventQueue,
                log: BridgeLog) {
        self.socketPath = socketPath
        self.eventQueue = eventQueue
        self.log = log
    }

    public func start() throws {
        try? FileManager.default.removeItem(atPath: socketPath)

        let params = NWParameters.tcp // TCP params, then swap endpoint to UDS
        params.requiredLocalEndpoint = .unix(path: socketPath)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            self.handle(connection: conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.log.info("bridge UDS listener state: \(state)")
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        var buffer = Data()
        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
                [weak self] data, _, isComplete, _ in
                guard let self else { return }
                if let data, !data.isEmpty {
                    buffer.append(data)
                    while let nl = buffer.firstIndex(of: 0x0A) {
                        let lineData = buffer[..<nl]
                        buffer.removeSubrange(...nl)
                        if let line = String(data: Data(lineData), encoding: .utf8),
                           let event = BridgeServer.parseLine(line) {
                            self.eventQueue.enqueue(event)
                        }
                    }
                }
                if isComplete {
                    connection.cancel()
                    return
                }
                receiveMore()
            }
        }
        receiveMore()
    }
```

Also add at the top:

```swift
import Network
```

**Note**: `NWEndpoint` does not expose `.unix(path:)` publicly; on recent macOS SDKs use `NWEndpoint.unixDomainSocketPath(_:)` if available. If the NWParameters-with-UDS approach fails to compile on 5.9/macOS 13, **fall back to a `POSIX` listener**: spawn a plain BSD socket + `DispatchSource.makeReadSource`, parse lines the same way, feed the queue. The parser is the same; only the acceptor changes. Whichever path you choose, gate the integration test on the working one.

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: the integration test passes. If `NWListener` UDS support is missing, swap to the POSIX fallback described above and re-run.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/BridgeServer.swift SnapBackApp/Tests/BridgeTests/BridgeServerTests.swift
git commit -m "feat(bridge): UDS listener feeds EventQueue from snapback-poke"
```

---

## Phase 11 — `MobilePeer` (TCP + heartbeat + resync)

### Task 11.1: `TestFakePhone` harness

**Files:**
- Create: `SnapBackApp/Tests/BridgeTests/TestFakePhone.swift`

- [ ] **Step 1: Write `TestFakePhone.swift`**

```swift
import Foundation
import Network
@testable import SnapBackApp

/// In-process TCP peer used by Swift tests. Accepts one connection at a time,
/// verifies incoming HMACs against a shared secret, and replies to `hello` with
/// `ack`, to `heartbeat` with `pong`, and to `resync` with a synthetic pong.
/// Fails (and records the reason) on any HMAC mismatch.
final class TestFakePhone {
    let port: NWEndpoint.Port
    let secret: Data
    private var listener: NWListener?
    private(set) var failureReason: String?
    private(set) var receivedTypes: [String] = []

    init(port: UInt16 = 0, secret: Data) throws {
        self.port = port == 0 ? .any : NWEndpoint.Port(rawValue: port)!
        self.secret = secret
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    var actualPort: UInt16? {
        if case .port(let p) = listener?.port { return p.rawValue } else { return nil }
    }

    func stop() { listener?.cancel() }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        var buffer = Data()
        func loop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                [weak self] data, _, isComplete, _ in
                guard let self else { return }
                if let data, !data.isEmpty {
                    buffer.append(data)
                    while let nl = buffer.firstIndex(of: 0x0A) {
                        let line = String(data: buffer[..<nl], encoding: .utf8) ?? ""
                        buffer.removeSubrange(...nl)
                        self.process(line: line, on: conn)
                    }
                }
                if isComplete { conn.cancel(); return }
                loop()
            }
        }
        loop()
    }

    private func process(line: String, on conn: NWConnection) {
        do {
            let (msg, hmac) = try MessageCodec.decodeLine(line + "\n")
            guard MessageCodec.verify(message: msg, direction: .clientToServer,
                                      hmacHex: hmac, secret: secret) else {
                failureReason = "bad hmac for \(msg.type.rawValue)"
                return
            }
            receivedTypes.append(msg.type.rawValue)
            // Synthesize a reply for hello/heartbeat/resync.
            switch msg.type {
            case .hello:
                respond(type: .ack, payload: [], on: conn)
            case .heartbeat:
                respond(type: .pong, payload: [("hold", .bool(false))], on: conn)
            case .resync:
                respond(type: .pong, payload: [("hold", .bool(false))], on: conn)
            default:
                break
            }
        } catch {
            failureReason = "\(error)"
        }
    }

    private func respond(type: ProtocolMessageType,
                         payload: [(String, JSONValue)],
                         on conn: NWConnection) {
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
                             .map { String(format: "%02x", $0) }.joined()
        let msg = ProtocolMessage(
            version: 1, type: type, timestamp: Int64(Date().timeIntervalSince1970),
            nonceHex: nonce, payload: payload
        )
        if let line = try? MessageCodec.encodeSignedLine(msg, direction: .serverToClient, secret: secret) {
            conn.send(content: Data(line.utf8), completion: .idempotent)
        }
    }
}
```

- [ ] **Step 2: Run the full suite to ensure compilation**

Run: `cd SnapBackApp && swift test`
Expected: previous tests still pass; no test for TestFakePhone itself yet (it's a harness).

- [ ] **Step 3: Commit**

```bash
git add SnapBackApp/Tests/BridgeTests/TestFakePhone.swift
git commit -m "test(bridge): TestFakePhone harness (in-process verifying peer)"
```

### Task 11.2: `MobilePeer` hello + ack (TDD)

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/MobilePeer.swift`
- Create: `SnapBackApp/Tests/BridgeTests/MobilePeerTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import Network
@testable import SnapBackApp

final class MobilePeerTests: XCTestCase {
    func testHelloAckHandshake() throws {
        let secret = Data(repeating: 0x42, count: 32)
        let phone = try TestFakePhone(secret: secret); try phone.start()
        defer { phone.stop() }
        // Wait for listener to bind
        var port: UInt16 = 0
        for _ in 0..<20 {
            if let p = phone.actualPort, p > 0 { port = p; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertGreaterThan(port, 0)

        let peer = MobilePeer(host: "127.0.0.1", port: port,
                              secret: secret, peerName: "HamperMBP")
        let exp = expectation(description: "ack received")
        peer.onStateChange = { state in
            if state == .connected { exp.fulfill() }
        }
        peer.start()
        wait(for: [exp], timeout: 3.0)
        peer.stop()
        XCTAssertEqual(phone.receivedTypes, ["hello"])
        XCTAssertNil(phone.failureReason)
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `MobilePeer.swift`**

```swift
import Foundation
import Network

public final class MobilePeer {
    public enum State: Equatable { case idle, connecting, connected, disconnected }

    public var onStateChange: ((State) -> Void)?
    public var onMessage: ((ProtocolMessage) -> Void)?

    private let host: String
    private let port: UInt16
    private let secret: Data
    private let peerName: String
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.snapback.bridge.mobilePeer")
    private var state: State = .idle { didSet { onStateChange?(state) } }
    private var reconnectAttempt = 0
    private var buffer = Data()

    public init(host: String, port: UInt16, secret: Data, peerName: String) {
        self.host = host
        self.port = port
        self.secret = secret
        self.peerName = peerName
    }

    public func start() {
        queue.async { self.connect() }
    }

    public func stop() {
        queue.async {
            self.state = .disconnected
            self.connection?.cancel()
            self.connection = nil
        }
    }

    public func send(_ message: ProtocolMessage) {
        queue.async {
            guard let conn = self.connection, self.state == .connected else { return }
            if let line = try? MessageCodec.encodeSignedLine(
                message, direction: .clientToServer, secret: self.secret) {
                conn.send(content: Data(line.utf8), completion: .idempotent)
            }
        }
    }

    private func connect() {
        state = .connecting
        let c = NWConnection(host: NWEndpoint.Host(host),
                             port: NWEndpoint.Port(rawValue: port)!,
                             using: .tcp)
        connection = c
        c.stateUpdateHandler = { [weak self] s in
            guard let self else { return }
            switch s {
            case .ready:
                self.reconnectAttempt = 0
                self.sendHello()
                self.receiveLoop()
            case .failed, .cancelled:
                self.state = .disconnected
            default:
                break
            }
        }
        c.start(queue: queue)
    }

    private func sendHello() {
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
                             .map { String(format: "%02x", $0) }.joined()
        let msg = ProtocolMessage(
            version: 1, type: .hello,
            timestamp: Int64(Date().timeIntervalSince1970),
            nonceHex: nonce,
            payload: [("app_version", .string("1.3.0")),
                      ("peer_name", .string(peerName))]
        )
        if let line = try? MessageCodec.encodeSignedLine(msg, direction: .clientToServer, secret: secret) {
            connection?.send(content: Data(line.utf8), completion: .idempotent)
        }
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, _ in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                while let nl = self.buffer.firstIndex(of: 0x0A) {
                    let line = String(data: self.buffer[..<nl], encoding: .utf8) ?? ""
                    self.buffer.removeSubrange(...nl)
                    self.dispatch(line: line)
                }
            }
            if isComplete { self.state = .disconnected; return }
            self.receiveLoop()
        }
    }

    private func dispatch(line: String) {
        guard let (msg, hmac) = try? MessageCodec.decodeLine(line + "\n") else { return }
        guard MessageCodec.verify(message: msg, direction: .serverToClient,
                                  hmacHex: hmac, secret: secret) else { return }
        // Any valid signed inbound message means we're connected.
        if state != .connected { state = .connected }
        onMessage?(msg)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: `testHelloAckHandshake` passes.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/MobilePeer.swift SnapBackApp/Tests/BridgeTests/MobilePeerTests.swift
git commit -m "feat(bridge): MobilePeer NWConnection client with hello/ack handshake"
```

### Task 11.3: Exponential reconnect on peer cancel (TDD)

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Bridge/MobilePeer.swift`
- Modify: `SnapBackApp/Tests/BridgeTests/MobilePeerTests.swift`

- [ ] **Step 1: Write failing test**

Append to `MobilePeerTests.swift`:

```swift
    func testReconnectsAfterPhoneRestart() throws {
        let secret = Data(repeating: 0x42, count: 32)
        var phone = try TestFakePhone(secret: secret); try phone.start()
        var port: UInt16 = 0
        for _ in 0..<20 { if let p = phone.actualPort, p > 0 { port = p; break }; Thread.sleep(forTimeInterval: 0.05) }

        let peer = MobilePeer(host: "127.0.0.1", port: port, secret: secret, peerName: "t")
        let connectedOnce = expectation(description: "connected once")
        let connectedTwice = expectation(description: "connected again")
        var seen = 0
        peer.onStateChange = { s in
            if s == .connected {
                seen += 1
                if seen == 1 { connectedOnce.fulfill() }
                else if seen == 2 { connectedTwice.fulfill() }
            }
        }
        peer.start()
        wait(for: [connectedOnce], timeout: 3.0)

        // Kill the phone, spin up a replacement on the same port.
        phone.stop()
        Thread.sleep(forTimeInterval: 0.2)
        phone = try TestFakePhone(port: port, secret: secret)
        try phone.start()
        wait(for: [connectedTwice], timeout: 10.0)
        peer.stop(); phone.stop()
    }
```

- [ ] **Step 2: Run, confirm fail (no reconnect logic)**

- [ ] **Step 3: Extend `MobilePeer.swift`**

Replace the `.failed, .cancelled` arm with:

```swift
            case .failed, .cancelled:
                self.state = .disconnected
                self.scheduleReconnect()
```

Add:

```swift
    private func scheduleReconnect() {
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        let delays: [TimeInterval] = [0.5, 2.0, 8.0, 30.0]
        let d = attempt < delays.count ? delays[attempt] : 120.0
        queue.asyncAfter(deadline: .now() + d) { [weak self] in
            guard let self else { return }
            guard self.state == .disconnected else { return }
            self.connect()
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: both `MobilePeerTests` cases pass. Reconnect test takes ~1–3 s.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/MobilePeer.swift SnapBackApp/Tests/BridgeTests/MobilePeerTests.swift
git commit -m "feat(bridge): MobilePeer exponential reconnect (0.5/2/8/30/120 s)"
```

### Task 11.4: `HeartbeatLoop` (TDD)

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/HeartbeatLoop.swift`
- Create: `SnapBackApp/Tests/BridgeTests/HeartbeatLoopTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import SnapBackApp

final class HeartbeatLoopTests: XCTestCase {
    func testFiresPingAtInterval() {
        var pings = 0
        let loop = HeartbeatLoop(intervalSeconds: 0.1, missesBeforeDead: 3)
        loop.onPing = { pings += 1 }
        loop.start()
        Thread.sleep(forTimeInterval: 0.35)
        loop.stop()
        XCTAssertGreaterThanOrEqual(pings, 2)
    }

    func testDeclaresDeadAfterMissedPongs() {
        let exp = expectation(description: "dead")
        let loop = HeartbeatLoop(intervalSeconds: 0.05, missesBeforeDead: 2)
        loop.onPing = { /* do not ack */ }
        loop.onDeadPeer = { exp.fulfill() }
        loop.start()
        wait(for: [exp], timeout: 2.0)
        loop.stop()
    }

    func testAckResetsMissCount() {
        let loop = HeartbeatLoop(intervalSeconds: 0.05, missesBeforeDead: 2)
        var deadCalls = 0
        loop.onDeadPeer = { deadCalls += 1 }
        loop.onPing = { loop.recordPong() }
        loop.start()
        Thread.sleep(forTimeInterval: 0.35)
        loop.stop()
        XCTAssertEqual(deadCalls, 0)
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `HeartbeatLoop.swift`**

```swift
import Foundation

public final class HeartbeatLoop {
    public var onPing: (() -> Void)?
    public var onDeadPeer: (() -> Void)?

    private let interval: TimeInterval
    private let missesBeforeDead: Int
    private let queue = DispatchQueue(label: "com.snapback.bridge.heartbeat")
    private var timer: DispatchSourceTimer?
    private var missesSinceLastPong = 0

    public init(intervalSeconds: TimeInterval = 30, missesBeforeDead: Int = 2) {
        self.interval = intervalSeconds
        self.missesBeforeDead = missesBeforeDead
    }

    public func start() {
        queue.async { [weak self] in
            self?.restartTimer()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    public func recordPong() {
        queue.async { [weak self] in
            self?.missesSinceLastPong = 0
        }
    }

    private func restartTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.missesSinceLastPong += 1
            if self.missesSinceLastPong >= self.missesBeforeDead {
                self.onDeadPeer?()
                return
            }
            self.onPing?()
        }
        t.resume()
        timer = t
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: three `HeartbeatLoopTests` cases pass.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/HeartbeatLoop.swift SnapBackApp/Tests/BridgeTests/HeartbeatLoopTests.swift
git commit -m "feat(bridge): HeartbeatLoop with miss-count dead-peer detection"
```

---

## Phase 12 — `BridgeOrchestrator` (glue + state machine)

### Task 12.1: Orchestrator receives queue events, sends to peer, handles resume/resync/heartbeat (TDD)

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/BridgeOrchestrator.swift`
- Create: `SnapBackApp/Tests/BridgeTests/BridgeOrchestratorTests.swift`

- [ ] **Step 1: Write failing end-to-end test**

```swift
import XCTest
@testable import SnapBackApp

final class BridgeOrchestratorTests: XCTestCase {
    func testAttentionEventIsSentToPhone() throws {
        let secret = Data(repeating: 0x42, count: 32)
        let phone = try TestFakePhone(secret: secret); try phone.start()
        var port: UInt16 = 0
        for _ in 0..<20 { if let p = phone.actualPort, p > 0 { port = p; break }; Thread.sleep(forTimeInterval: 0.05) }

        let queue = EventQueue()
        let peer = MobilePeer(host: "127.0.0.1", port: port, secret: secret, peerName: "orch")
        let orch = BridgeOrchestrator(eventQueue: queue, peer: peer, status: BridgeStatusPublisher())
        orch.start()
        defer { orch.stop() }

        // Wait for the hello handshake to complete.
        for _ in 0..<40 {
            if phone.receivedTypes.contains("hello") { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        queue.enqueue(.attention(kind: "Stop"))

        for _ in 0..<40 {
            if phone.receivedTypes.contains("attention") { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(phone.receivedTypes.contains("attention"))
        XCTAssertNil(phone.failureReason)
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `BridgeOrchestrator.swift`**

```swift
import Foundation

public final class BridgeOrchestrator {
    private let eventQueue: EventQueue
    private let peer: MobilePeer
    private let status: BridgeStatusPublisher
    private let drainQueue = DispatchQueue(label: "com.snapback.bridge.orchestrator")
    private var drainTimer: DispatchSourceTimer?
    private var holdOutstanding = false
    private let heartbeat: HeartbeatLoop

    public init(eventQueue: EventQueue,
                peer: MobilePeer,
                status: BridgeStatusPublisher,
                heartbeat: HeartbeatLoop = HeartbeatLoop(intervalSeconds: 30, missesBeforeDead: 2)) {
        self.eventQueue = eventQueue
        self.peer = peer
        self.status = status
        self.heartbeat = heartbeat

        peer.onStateChange = { [weak self] s in
            guard let self else { return }
            switch s {
            case .connected:   self.status.update(.connected);   self.sendResync()
            case .connecting:  self.status.update(.connecting)
            case .disconnected:self.status.update(.unreachable); self.heartbeat.stop()
            case .idle:        self.status.update(.unpaired)
            }
        }
        peer.onMessage = { [weak self] msg in self?.handleInbound(msg) }

        heartbeat.onPing = { [weak self] in self?.sendHeartbeat() }
        heartbeat.onDeadPeer = { [weak self] in self?.holdOutstanding = false }
    }

    public func start() {
        peer.start()
        let t = DispatchSource.makeTimerSource(queue: drainQueue)
        t.schedule(deadline: .now(), repeating: 0.1)
        t.setEventHandler { [weak self] in self?.drain() }
        t.resume()
        drainTimer = t
    }

    public func stop() {
        drainTimer?.cancel()
        drainTimer = nil
        heartbeat.stop()
        peer.stop()
    }

    private func drain() {
        while let event = eventQueue.pop() {
            switch event {
            case .attention(let kind):
                send(.attention, payload: [("hook", .string(kind))])
                holdOutstanding = true
                heartbeat.start()
            case .resume:
                send(.resume, payload: [])
                holdOutstanding = false
                heartbeat.stop()
            }
        }
    }

    private func send(_ type: ProtocolMessageType, payload: [(String, JSONValue)]) {
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
                             .map { String(format: "%02x", $0) }.joined()
        let msg = ProtocolMessage(
            version: 1, type: type,
            timestamp: Int64(Date().timeIntervalSince1970),
            nonceHex: nonce, payload: payload
        )
        peer.send(msg)
    }

    private func sendResync() { send(.resync, payload: []) }
    private func sendHeartbeat() { send(.heartbeat, payload: []) }

    private func handleInbound(_ msg: ProtocolMessage) {
        switch msg.type {
        case .pong:
            heartbeat.recordPong()
            if case let .bool(phoneHold)? = msg.payload.first(where: { $0.0 == "hold" })?.1 {
                // Mac mirrors phone's ground truth on resync/pong.
                holdOutstanding = phoneHold
                if !phoneHold { heartbeat.stop() }
            }
        case .ack:
            break
        case .invalidate:
            // Received back from phone unexpectedly; ignore.
            break
        default:
            break
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SnapBackApp && swift test`
Expected: test passes, phone sees `hello`, `resync`, `attention`.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/BridgeOrchestrator.swift SnapBackApp/Tests/BridgeTests/BridgeOrchestratorTests.swift
git commit -m "feat(bridge): BridgeOrchestrator glue with resync + heartbeat hooks"
```

---

## Phase 13 — `MDNSBrowser`

### Task 13.1: Discover `_snapback._tcp.local` via `NWBrowser` (TDD)

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/MDNSBrowser.swift`
- Create: `SnapBackApp/Tests/BridgeTests/MDNSBrowserTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import Network
@testable import SnapBackApp

final class MDNSBrowserTests: XCTestCase {
    func testDiscoversLocalAdvertisement() throws {
        // Advertise a test service from another NWListener (this process).
        let listener = try NWListener(using: .tcp, on: .any)
        listener.service = NWListener.Service(name: "snapback-test-\(UUID().uuidString)",
                                              type: "_snapback._tcp",
                                              domain: "local.",
                                              txtRecord: nil)
        listener.newConnectionHandler = { _ in }
        listener.start(queue: .global(qos: .userInitiated))
        defer { listener.cancel() }

        let exp = expectation(description: "discovered")
        let browser = MDNSBrowser()
        browser.onDiscover = { host, port in
            if port > 0 { exp.fulfill() }
        }
        browser.start()
        wait(for: [exp], timeout: 5.0)
        browser.stop()
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `MDNSBrowser.swift`**

```swift
import Foundation
import Network

public final class MDNSBrowser {
    public var onDiscover: ((String, UInt16) -> Void)?

    private var browser: NWBrowser?
    private var pathMonitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.snapback.bridge.mdns")

    public init() {}

    public func start() {
        startBrowser()
        let pm = NWPathMonitor()
        pm.pathUpdateHandler = { [weak self] _ in
            self?.queue.async {
                self?.browser?.cancel()
                self?.startBrowser()
            }
        }
        pm.start(queue: queue)
        pathMonitor = pm
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func startBrowser() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_snapback._tcp", domain: "local.")
        let b = NWBrowser(for: descriptor, using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results {
                switch r.endpoint {
                case let .service(name, _, _, _):
                    self?.resolve(endpoint: r.endpoint, name: name)
                default:
                    break
                }
            }
        }
        b.start(queue: queue)
        browser = b
    }

    private func resolve(endpoint: NWEndpoint, name: String) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if case let .hostPort(host, port) = conn.currentPath?.remoteEndpoint {
                    let hostString: String
                    switch host {
                    case .name(let s, _): hostString = s
                    case .ipv4(let ipv4): hostString = "\(ipv4)"
                    case .ipv6(let ipv6): hostString = "\(ipv6)"
                    @unknown default: hostString = "unknown"
                    }
                    self?.onDiscover?(hostString, port.rawValue)
                }
                conn.cancel()
            }
        }
        conn.start(queue: queue)
    }
}
```

- [ ] **Step 4: Run test**

Run: `cd SnapBackApp && swift test`
Expected: `testDiscoversLocalAdvertisement` passes.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/MDNSBrowser.swift SnapBackApp/Tests/BridgeTests/MDNSBrowserTests.swift
git commit -m "feat(bridge): MDNSBrowser discovers _snapback._tcp.local peers"
```

---

## Phase 14 — Pairing

### Task 14.1: Pair token generator + QR payload (TDD)

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Bridge/Pairing.swift`
- Create: `SnapBackApp/Tests/BridgeTests/PairingTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import SnapBackApp

final class PairingTests: XCTestCase {
    func testPairingURLShape() {
        let token = Data((0..<32).map { UInt8($0) })
        let url = Pairing.pairingURL(token: token, deskName: "Hamper's MBP")
        XCTAssertTrue(url.hasPrefix("snapback-pair://v1?token="))
        XCTAssertTrue(url.contains("&desk=Hamper%27s%20MBP"))
        XCTAssertTrue(url.contains("&v=1"))
        // token hex is 64 chars
        let tokenPart = url
            .replacingOccurrences(of: "snapback-pair://v1?token=", with: "")
            .components(separatedBy: "&")
            .first!
        XCTAssertEqual(tokenPart.count, 64)
    }
}
```

- [ ] **Step 2: Run, confirm fail**

- [ ] **Step 3: Create `Pairing.swift`**

```swift
import Foundation
import CoreImage

public enum Pairing {
    public static func pairingURL(token: Data, deskName: String) -> String {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        var comps = URLComponents()
        comps.scheme = "snapback-pair"
        comps.host = "v1"
        comps.queryItems = [
            URLQueryItem(name: "token", value: hex),
            URLQueryItem(name: "desk", value: deskName),
            URLQueryItem(name: "v", value: "1")
        ]
        // URLComponents encodes "//v1" as a host; rebuild string to match our documented form.
        return "snapback-pair://v1?" + (comps.query ?? "")
    }

    public static func qrImage(for url: String, scale: CGFloat = 8.0) -> CGImage? {
        guard let data = url.data(using: .utf8) else { return nil }
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(transformed, from: transformed.extent)
    }
}
```

- [ ] **Step 4: Run tests**

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Bridge/Pairing.swift SnapBackApp/Tests/BridgeTests/PairingTests.swift
git commit -m "feat(bridge): Pairing URL + CoreImage QR generator"
```

---

## Phase 15 — Menu-bar integration

### Task 15.1: `MobileTabView` — renders status dot + pair button

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Views/MobileTabView.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

struct MobileTabView: View {
    @ObservedObject var status: BridgeStatusPublisher
    var onPair: () -> Void
    var onUnpair: () -> Void
    var qrImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mobile")
                    .font(.headline)
                Spacer()
                statusDot
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Divider()
            if let qr = qrImage {
                Image(decorative: qr, scale: 1.0, orientation: .up)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                Text("Scan with SnapBack Mobile to pair.")
                    .font(.footnote)
                Button("Cancel", action: onUnpair)
            } else {
                switch status.current {
                case .unpaired:
                    Button("Pair mobile…", action: onPair)
                case .connected:
                    Text("Paired & connected.")
                    Button("Unpair", role: .destructive, action: onUnpair)
                case .connecting, .unreachable:
                    Text("Searching for phone…")
                case .error(let msg):
                    Text("Error: \(msg)").foregroundColor(.red)
                    Button("Retry pair", action: onPair)
                }
            }
        }
        .padding(10)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch status.current {
        case .connected:  return .green
        case .connecting, .unreachable: return .yellow
        case .error:      return .red
        case .unpaired:   return .gray
        }
    }

    private var statusText: String {
        switch status.current {
        case .connected: return "connected"
        case .connecting: return "connecting…"
        case .unreachable: return "unreachable"
        case .error: return "error"
        case .unpaired: return "unpaired"
        }
    }
}
```

- [ ] **Step 2: Build (no test yet — SwiftUI views are best tested via UI)**

Run: `cd SnapBackApp && swift build`
Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Views/MobileTabView.swift
git commit -m "feat(bridge): MobileTabView (status dot, pair QR, unpair)"
```

### Task 15.2: Wire `BridgeOrchestrator` into `SnapBackApp.swift` and embed `MobileTabView` in `MenuBarView`

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/SnapBackApp.swift`
- Modify: `SnapBackApp/Sources/SnapBackApp/Views/MenuBarView.swift`

- [ ] **Step 1: Inspect the current entry point**

Run: `cat SnapBackApp/Sources/SnapBackApp/SnapBackApp.swift`

- [ ] **Step 2: Add a `BridgeRuntime` singleton that owns status + orchestrator + pairing**

Append to `SnapBackApp.swift` (outside any existing struct):

```swift
final class BridgeRuntime: ObservableObject {
    static let shared = BridgeRuntime()

    let status = BridgeStatusPublisher()
    @Published var pendingQRURL: String?

    private let tokenStore = KeychainTokenStore()
    private let eventQueue = EventQueue()
    private let log: BridgeLog
    private var bridgeServer: BridgeServer?
    private var peer: MobilePeer?
    private var orchestrator: BridgeOrchestrator?
    private var browser: MDNSBrowser?

    init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/SnapBack")
        self.log = BridgeLog(directory: dir)
    }

    func start() {
        let sockEnv = ProcessInfo.processInfo.environment["SNAPBACK_BRIDGE_SOCKET"]
        let sock = sockEnv ?? (NSTemporaryDirectory() + "snapback-bridge.sock")
        let server = BridgeServer(socketPath: sock, eventQueue: eventQueue, log: log)
        try? server.start()
        bridgeServer = server

        // If already paired, try to reach the phone.
        if let token = tokenStore.read() {
            let browser = MDNSBrowser()
            browser.onDiscover = { [weak self] host, port in
                guard let self else { return }
                if self.peer != nil { return }
                let deskName = Host.current().localizedName ?? "Mac"
                let peer = MobilePeer(host: host, port: port, secret: token, peerName: deskName)
                let orch = BridgeOrchestrator(eventQueue: self.eventQueue, peer: peer, status: self.status)
                orch.start()
                self.peer = peer
                self.orchestrator = orch
            }
            browser.start()
            self.browser = browser
        }
    }

    func pair() {
        do {
            let token = try tokenStore.generateAndStore()
            let desk = Host.current().localizedName ?? "Mac"
            pendingQRURL = Pairing.pairingURL(token: token, deskName: desk)
        } catch {
            status.update(.error("pair: \(error)"))
        }
    }

    func unpair() {
        orchestrator?.stop()
        peer = nil
        orchestrator = nil
        try? tokenStore.delete()
        pendingQRURL = nil
        status.update(.unpaired)
    }
}
```

And in the `@main` struct's `init()` (or the `body` scene handler, depending on the current code), call `BridgeRuntime.shared.start()` on app launch.

- [ ] **Step 3: Embed `MobileTabView` in `MenuBarView.swift`**

Read the current `MenuBarView.swift`. Find the outermost `VStack` or `Form` and append the tab:

```swift
Divider()
MobileTabView(
    status: BridgeRuntime.shared.status,
    onPair: { BridgeRuntime.shared.pair() },
    onUnpair: { BridgeRuntime.shared.unpair() },
    qrImage: BridgeRuntime.shared.pendingQRURL.flatMap { Pairing.qrImage(for: $0) }
)
```

- [ ] **Step 4: Build**

Run: `cd SnapBackApp && swift build`
Expected: compiles cleanly.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/SnapBackApp.swift SnapBackApp/Sources/SnapBackApp/Views/MenuBarView.swift
git commit -m "feat(bridge): wire BridgeRuntime into the menu-bar app"
```

---

## Phase 16 — CLI `snapback mobile` subcommands

### Task 16.1: `snapback mobile status | enable | disable | pair | unpair | logs`

**Files:**
- Modify: `snapback`
- Test: `tests/cli_typed.bats`

- [ ] **Step 1: Bump the version in `snapback:5`**

Change `VERSION="1.2.0"` to `VERSION="1.3.0"`.

- [ ] **Step 2: Add the `mobile` row to `show_help()` (line ~63)**

After the `app` row, add:

```
  mobile <sub> pair | unpair | status | enable | disable | logs
```

- [ ] **Step 3: Add `cmd_mobile()`**

Insert before the `# MAIN` block:

```bash
# ============================================================
# MOBILE COMMAND (1.3.0 bridge)
# ============================================================
cmd_mobile() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    enable)
      config_set MOBILE_ENABLED true
      print_success "MOBILE_ENABLED=true"
      ;;
    disable)
      config_set MOBILE_ENABLED false
      print_success "MOBILE_ENABLED=false"
      ;;
    status)
      local enabled
      enabled=$(config_get MOBILE_ENABLED 2>/dev/null || echo "false")
      echo ""
      echo "Mobile bridge"
      echo "─────────────"
      echo "  enabled: $enabled"
      echo "  socket:  ${SNAPBACK_BRIDGE_SOCKET:-unset}"
      if [[ -S "${SNAPBACK_BRIDGE_SOCKET:-}" ]]; then
        print_success "bridge socket is live"
      else
        print_warning "bridge socket not present (menu-bar app running?)"
      fi
      local dname
      dname=$(config_get MOBILE_DEVICE_NAME 2>/dev/null || echo "")
      if [[ -n "$dname" ]]; then
        print_info "  paired peer: $dname"
      else
        print_info "  no paired peer"
      fi
      echo ""
      ;;
    pair)
      # Delegate to the menu-bar app; the pairing UI lives there.
      cmd_app
      print_info "Opened SnapBackApp; use 'Pair mobile…' in the menu-bar popover."
      ;;
    unpair)
      # Delete keychain token via the helper binary if present; else warn.
      if command -v security >/dev/null 2>&1; then
        security delete-generic-password -s com.snapback.mobile -a pair-token >/dev/null 2>&1 || true
      fi
      config_set MOBILE_DEVICE_NAME "" || true
      config_set MOBILE_ENABLED false || true
      print_success "Unpaired (Keychain token cleared)."
      ;;
    logs)
      local log="$HOME/Library/Logs/SnapBack/bridge.log"
      if [[ -f "$log" ]]; then
        tail -n 200 "$log"
      else
        print_warning "no log file yet: $log"
      fi
      ;;
    "")
      print_error "Usage: snapback mobile <pair|unpair|status|enable|disable|logs>"
      exit 2
      ;;
    *)
      print_error "Unknown mobile subcommand: $sub"
      exit 2
      ;;
  esac
}
```

- [ ] **Step 4: Add the dispatcher case in `main()`**

Find the `case "$cmd" in` block. After `app) cmd_app ;;` add:

```bash
    mobile)
      cmd_mobile "$@"
      ;;
```

- [ ] **Step 5: Add a bats test**

Append to `tests/cli_typed.bats`:

```bash
@test "snapback mobile status prints basic info" {
  run snapback mobile status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mobile bridge"* ]]
  [[ "$output" == *"enabled:"* ]]
}

@test "snapback mobile enable sets MOBILE_ENABLED=true" {
  snapback mobile enable
  [ "$(snapback config get MOBILE_ENABLED)" = "true" ]
}

@test "snapback mobile disable sets MOBILE_ENABLED=false" {
  snapback mobile enable
  snapback mobile disable
  [ "$(snapback config get MOBILE_ENABLED)" = "false" ]
}
```

- [ ] **Step 6: Run**

Run: `bats tests/cli_typed.bats`
Expected: all original tests plus the three new ones pass.

- [ ] **Step 7: Commit**

```bash
git add snapback tests/cli_typed.bats
git commit -m "feat(bridge): snapback mobile CLI subcommands + bats coverage"
```

### Task 16.2: `cmd_uninstall` wipes the Keychain token

**Files:**
- Modify: `snapback` (in `cmd_uninstall`)

- [ ] **Step 1: Add the `security delete-generic-password` invocation**

Inside `cmd_uninstall`, after `# Remove config` block (around line 331) and before removing `/tmp/*` files, insert:

```bash
  # Remove Keychain token if any
  if command -v security >/dev/null 2>&1; then
    security delete-generic-password -s com.snapback.mobile -a pair-token >/dev/null 2>&1 || true
    print_success "Removed Keychain entry (if present)"
  fi
```

- [ ] **Step 2: Commit**

```bash
git add snapback
git commit -m "feat(bridge): uninstall wipes com.snapback.mobile Keychain entry"
```

---

## Phase 17 — Protocol reference and README

### Task 17.1: Write `docs/PROTOCOL.md` (frozen spec of wire protocol)

**Files:**
- Create: `docs/PROTOCOL.md`

- [ ] **Step 1: Create the doc**

```markdown
# SnapBack Bridge Wire Protocol (v1, frozen in 1.3.0)

Canonical description of the signed JSON-over-TCP protocol spoken between the
Mac bridge (inside SnapBackApp) and the Android SnapBack Mobile app.

## Transport
- TCP on port 45782 (default; fixed in v1).
- Phone listens, Mac connects.
- mDNS service type `_snapback._tcp.local`.
- No TLS: confidentiality is unnecessary, messages contain no sensitive data.

## Framing
- One JSON object per line, UTF-8, LF-terminated (`\n`).

## Message shape
```json
{
  "v": 1,
  "type": "hello" | "ack" | "attention" | "resume" | "heartbeat" | "pong" | "resync" | "invalidate",
  "ts": <int, unix seconds>,
  "nonce": "<32 lowercase hex chars>",
  "payload": { ... },
  "hmac": "<64 lowercase hex chars>"
}
```

## Signing domain (byte-exact)

Concatenate, null-separated (`\x00`), in this order:

```
dir  \x00  v  \x00  type  \x00  ts  \x00  nonce  \x00  payload_bytes
```

- `dir`:     `c2s` (Mac→Phone) or `s2c` (Phone→Mac), ASCII.
- `v`, `ts`: base-10 ASCII, no leading zeros.
- `type`:    lowercase ASCII, from the set above.
- `nonce`:   32 lowercase hex chars exactly.
- `payload_bytes`: canonical JSON of the `payload` object: sorted keys, UTF-8, no whitespace, `{}` for empty. Strings escape only `\\`, `\"`, `\n`, `\r`, `\t`, `\b`, `\f`, and control chars as `\uXXXX`.

Take `HMAC-SHA256(secret, domain)` and emit as 64 lowercase hex chars as `hmac`.

The `hmac` field is NOT part of the signing domain. Framing bytes (LF) are NOT signed.

## Replay protection

- `ts` must be within ±30 s of the receiver's clock.
- `nonce` is cached for 10 minutes **per shared secret**; duplicates are rejected.
- Nonce TTL is strictly greater than the ts window; this invariant must not be narrowed.

## Event semantics

| Type | Direction | Payload | Effect |
|---|---|---|---|
| `hello` | c2s | `{"peer_name": "<str>", "app_version": "<str>"}` | Opens session; phone replies `ack`. |
| `ack` | s2c | `{}` | Acknowledges `hello`. |
| `attention` | c2s | `{"hook": "PermissionRequest" \| "Stop"}` | Phone evaluates gate + enters HOLD. |
| `resume` | c2s | `{}` | Phone exits HOLD. |
| `heartbeat` | c2s | `{}` | Sent every 30 s while HOLD outstanding. |
| `pong` | s2c | `{"hold": <bool>}` | Reply to `heartbeat` or `resync`. |
| `resync` | c2s | `{}` | Asks phone for its current HOLD state on (re)connect. |
| `invalidate` | c2s | `{}` | Best-effort pre-unpair notice. Phone wipes its token on receipt. |

## Test vectors

`tests/protocol-vectors.json` ships with SnapBack and is consumed by both the
Swift and Kotlin test suites. Any change to this file is a protocol change and
requires a `v` bump.
```

- [ ] **Step 2: Commit**

```bash
git add docs/PROTOCOL.md
git commit -m "docs(bridge): freeze v1 wire protocol reference"
```

### Task 17.2: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append a new section**

At the bottom of `README.md`:

```markdown
## Mobile (experimental, 1.3.0 preview)

1.3.0 ships the desktop side of a mobile companion: a persistent bridge daemon
inside SnapBackApp that will talk to a future Android app to force-lock your
phone when Claude Code blocks on you. No phone app is shipped yet. The bridge
is feature-complete against `docs/PROTOCOL.md` and can be tested against an
in-process Swift peer.

Turn it on:

```sh
snapback mobile enable
snapback mobile status
```

When the Android companion ships in 1.4.0, the menu-bar app will show a "Pair
mobile…" QR that completes the link. Until then, `snapback mobile status`
reports whether the bridge socket is live. See `docs/superpowers/specs/2026-04-18-mobile-companion-design.md`
for the full design.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(bridge): README section for 1.3.0 mobile preview"
```

---

## Phase 18 — Release 1.3.0

### Task 18.1: CHANGELOG-style entry on the merge commit (no separate changelog file today)

**Files:** none (summary commit after squash if desired; the per-task commits are the canonical history).

- [ ] **Step 1: Confirm all tests pass**

Run: `cd SnapBackApp && swift test && cd .. && bats tests/`
Expected: every suite green.

- [ ] **Step 2: Build the app bundle end-to-end**

Run: `cd SnapBackApp && ./build-app.sh`
Expected: bundle built, version 1.3.0, `snapback-poke` included.

- [ ] **Step 3: Verify the hook flow manually**

```bash
# In one terminal — start the menu-bar app
open SnapBackApp/SnapBack.app
# In another terminal
snapback mobile enable
snapback mobile status
# trigger a hook
./snapback.sh
# check that a bridge log line was written
tail -n 5 ~/Library/Logs/SnapBack/bridge.log
```

Expected: log shows the event was enqueued; no errors.

- [ ] **Step 4: Tag 1.3.0**

```bash
git tag -a v1.3.0 -m "SnapBack 1.3.0 — desktop bridge for future mobile companion"
```

- [ ] **Step 5: Push when ready (this is user-gated — do not push without confirmation)**

If the user authorizes, then:

```bash
git push origin main
git push origin v1.3.0
```

---

## Self-Review (Plan vs Spec)

**Spec coverage checklist:**

| Spec section | Covered by |
|---|---|
| §2 "Bridge process model" (compiled poke helper) | Phase 2 (Tasks 2.1–2.5) |
| §2 "Sandbox posture" | Declarative only in docs + README; no code path gated on it — consistent with spec. |
| §4.1 Wire format + signing domain | Phase 5 (Tasks 5.1–5.5) |
| §4.1 Replay invariant (nonce TTL > ts window) | Phase 6 (NonceCache) + enforced by `BridgeOrchestrator` applying the codec. |
| §4.2 All 8 message types | Enumerated in MessageCodec (Task 5.1); exercised in fake-phone tests (Task 11.1) + orchestrator (Task 12.1). |
| §4.3 Pairing (token + QR + URL scheme) | Phase 14 (Task 14.1) + Menu-bar wiring (Task 15.2). |
| §4.4 Unpair (Keychain delete + best-effort invalidate) | Task 16.1 + Task 16.2. *Note:* MVP sends no `invalidate` over the wire on unpair — this is acceptable per spec "best effort" but explicit follow-up: add `peer.send(invalidate)` before `delete()` in `BridgeRuntime.unpair()`. **Added below.** |
| §5.1 Hook script changes | Phase 3 (Tasks 3.1–3.3). |
| §5.2 Bridge daemon components | Phases 6–13. |
| §5.5 Status surfaces | Task 9.1 + 15.1 + 16.1 (`status`/`logs`). **Menu-bar dot** is covered; **macOS user notifications on state transition** are NOT — see gap below. |
| §5.6 Config surface (known keys diff + CLI) | Phase 1 + Phase 16. |
| §5.7 Forward compatibility (v field + per-peer token) | Frozen in Phase 5 codec + pair flow. |
| §5.9 Distribution (1.3.0 via existing installer) | Task 2.5 + 18.x. |
| §6 Error handling table | Most rows are handled in code. Rate-limit on HMAC mismatches on the *Mac side* is not explicitly added — acceptable because the Mac only receives from one known peer, and a torrent of malformed inbound traffic from the paired phone is not a threat model. **Not a gap.** |
| §7 Tests (bridge unit, integration, poke, latency, vectors) | Phases 2, 3, 5, 6, 7, 8, 10, 11, 12, 13. |

**Gaps discovered during self-review — adding inline tasks:**

### Task 15.3 (added): `invalidate` on unpair (spec §4.4)

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/SnapBackApp.swift` (`BridgeRuntime.unpair`)

- [ ] **Step 1: Edit `BridgeRuntime.unpair` to send `invalidate` BEFORE deleting the token**

Replace `unpair()` with:

```swift
func unpair() {
    // Send best-effort invalidate while we still have a valid signing secret.
    let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
                         .map { String(format: "%02x", $0) }.joined()
    let msg = ProtocolMessage(
        version: 1, type: .invalidate,
        timestamp: Int64(Date().timeIntervalSince1970),
        nonceHex: nonce, payload: []
    )
    peer?.send(msg)

    // Give the peer ~250 ms to drain the send buffer, then tear down.
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
        guard let self else { return }
        self.orchestrator?.stop()
        self.peer = nil
        self.orchestrator = nil
        try? self.tokenStore.delete()
        DispatchQueue.main.async {
            self.pendingQRURL = nil
            self.status.update(.unpaired)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/SnapBackApp.swift
git commit -m "feat(bridge): send invalidate on unpair before token deletion"
```

### Task 15.4 (added): macOS user notification on state transition (spec §5.5)

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/SnapBackApp.swift`

- [ ] **Step 1: Import UserNotifications and add a transition watcher**

In `BridgeRuntime.init()`, after `self.log = BridgeLog(...)`, add:

```swift
    private var cancellables: Set<AnyCancellable> = []

    private func installStatusTransitionNotifier() {
        var lastStatus: BridgeStatus = .unpaired
        status.$current
            .dropFirst()
            .sink { newStatus in
                defer { lastStatus = newStatus }
                guard lastStatus != newStatus else { return }
                switch (lastStatus, newStatus) {
                case (.connected, .unreachable), (.connected, .error):
                    BridgeRuntime.notify(title: "SnapBack", body: "Mobile unreachable")
                case (_, .connected) where lastStatus != .connecting:
                    BridgeRuntime.notify(title: "SnapBack", body: "Mobile reconnected")
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(req, withCompletionHandler: nil)
    }
```

Call `installStatusTransitionNotifier()` at the end of `start()`.

Add `import UserNotifications` and `import Combine` at the top of the file.

- [ ] **Step 2: Build**

Run: `cd SnapBackApp && swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/SnapBackApp.swift
git commit -m "feat(bridge): macOS user notifications on bridge state transitions"
```

---

## Not in this plan (1.4.0 or later)

- Android application (§5.3, §5.4, §5.8).
- Launchd agent for bridge auto-restart (§2 "Auto-restart" row — v2).
- Cloud relay (explicitly non-goal in §1).
- Sandboxing SnapBackApp (spec §2 "Sandbox posture" — future work row).
- Play Store submission (§5.9).
- iOS client (§1).

Each gets its own spec + plan when the 1.3.0 rollout lands and we have real usage data from the bridge-only release.
