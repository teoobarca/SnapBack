# SnapBack Mobile Companion — Design

Date: 2026-04-18
Status: Revised after code-reviewer pass; awaiting user approval
Target versions: **1.3.0** — desktop bridge (shippable alone); **1.4.0** — Android companion app
Scope note: this spec is a single vision but describes two rollouts. §8 splits them explicitly. Each rollout gets its own implementation plan.

## 1. Motivation

SnapBack currently redirects attention on the desktop: when Claude Code needs input, it plays a sound and focuses the IDE. This works when the user is *at* the computer. It does not work when the user has drifted to their phone — which is exactly where developers go during multi-minute agent runs.

Existing phone-focus tools (Opal, One Sec, ScreenZen) are stateless: they block by schedule or by app heuristics. They have no signal about whether a specific piece of work is genuinely waiting for the user right now.

Claude Code *does* have that signal. SnapBack already routes it into hooks. Extending the signal to the phone turns a generic focus app into a context-aware accountability system: the phone stays free while Claude is working, and actively intervenes the moment Claude blocks on the user.

### Goal

A companion Android application paired 1:1 with a Mac running SnapBack, such that:

- While Claude Code is working on the desktop, the phone behaves normally.
- When Claude transitions into a waiting state (`PermissionRequest` or `Stop` hook) **and** the phone is actively in use (screen on + unlocked), the phone force-locks.
- Re-unlocks by the user re-engage the lock, until SnapBack observes Claude resume (`UserPromptSubmit`).
- Desktop side adds no perceptible latency to existing Claude hooks.
- No backend, no cloud account, no ongoing service cost — consistent with SnapBack's local-first philosophy.

### Non-goals (for this spec)

- iOS support. iOS lacks the primitives (foreground service with lock capability, reliable mDNS while backgrounded) this design depends on. A separate spec is required if/when we address it.
- Remote (off-LAN) operation. "Phone on cellular data while Mac is on WiFi" is explicitly out of scope. **No cloud relay, ever, under this spec** — if we want remote operation we write a new spec; we do not smuggle it in as "future extension".
- Multi-device (N:M). MVP is 1 phone ↔ 1 Mac. Protocol leaves room for extension (§5.7).
- Displaying Claude's *prompt content* on the phone. Lock screen shows only that *something* is waiting and, optionally, which hook type triggered (`PermissionRequest` vs `Stop`) — no prompt text.
- A Claude Code client on the phone. Claude runs on the Mac; the phone only participates in the attention loop.
- Google Play distribution in 1.4.0. Distribution is **GitHub Releases APK sideload** (see §8.2 and §5.9). Play-store submission is a separate, later project with different constraints.

## 2. Design decisions (resolved during brainstorming + review)

| Question | Decision | Rationale |
|---|---|---|
| User scenario | Anti-distraction (user at PC, drifts to phone) | Matches the user's stated pain. |
| Intervention level | Hard force lock, **Accessibility `performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)` primary; Device Admin `lockNow()` fallback** | Accessibility path is the one that works without enterprise-admin review; Device Admin remains because sideload users can enable it for stricter behaviour. (Initial draft had these inverted; review flagged Play policy — §5.3.2.) |
| Trigger gate | Only when phone screen is on **and** unlocked | Phone in pocket = no-op. Quieter, less battery drain. |
| Transport | LAN / mDNS with HMAC-SHA256 over plain TCP | No backend, no accounts, fits SnapBack philosophy. Confidentiality unnecessary (no sensitive payload). |
| Platform (MVP) | Android only | Has Accessibility, Device Admin, foreground services. iOS cannot implement this cleanly. |
| Release condition | Auto-unlock only when Claude resume hook fires, with fail-safes (§5.4) | Strongest accountability; timeouts and heartbeats prevent lock-out bugs. |
| Pairing | QR code with 32-byte shared secret | Simple, offline, secure enough for LAN. |
| Device cardinality | 1 phone ↔ 1 Mac for MVP | Smallest footprint. Protocol forward-compatible with N:M. |
| Emergency PIN on phone | Not included | User declined; manual release in app is sufficient. |
| Bridge process model | Long-running daemon inside SnapBackApp; hook scripts talk to it via a **compiled C/Swift helper** (`snapback-poke`), not `nc` | `nc` without `-N` leaks processes; `nc -N` works but forks `/usr/bin/nc` (8–25 ms). A 40-line helper is negligible and eliminates fragility. |
| Sandbox posture of SnapBackApp | **Not sandboxed** in 1.3.0. Distributed as a locally-built `.app` dragged to `/Applications`; unsandboxed means UDS path outside `~/Library/Containers/` is fine. If sandboxing is ever adopted, the UDS moves into the app group container; this is called out as future work. | Matches current reality of the unification-spec menu-bar app. |
| Auto-restart (launchd) | v2, not MVP | "App is running = mobile is connected" is an acceptable MVP contract; menu-bar dot exposes state. |

## 3. Architecture

```
┌────────────────── Mac (SnapBack + Bridge) ──────────────────────────────┐
│                                                                          │
│  Claude Code ──hooks──▶ snapback.sh  ──▶ sound + focus (unchanged)      │
│                              │                                           │
│                              └──▶ snapback-poke attention   (& bg)      │
│                                        │                                 │
│                                        ▼                                 │
│                                   UDS client writes one                  │
│                                   framed message + EOF                   │
│                                        │                                 │
│                                        ▼                                 │
│                         ┌─────────── Bridge daemon ───────────┐         │
│                         │  (Swift, inside SnapBackApp)         │         │
│                         │  • UDS listener (accepts pokes)     │         │
│                         │  • NWBrowser: _snapback._tcp.local  │         │
│                         │  • persistent NWConnection + HB     │         │
│                         │  • HMAC sign; nonce + ts + dir      │         │
│                         │  • event queue + retry/backoff      │         │
│                         │  • publishes status to menu-bar UI  │         │
│                         │  • rolling log to ~/Library/Logs/   │         │
│                         └──────────────────┬──────────────────┘         │
│                                            │                             │
│  Claude Code ──UserPromptSubmit──▶ snapback-resume.sh                  │
│                                    ──▶ snapback-poke resume             │
└────────────────────────────────────────────┼─────────────────────────────┘
                                             │ TCP + HMAC + direction byte
                                             ▼
┌──────────────────── Android (SnapBack Mobile) ──────────────────────────┐
│                                                                          │
│  ForegroundService (persistent notification, WifiLock + MulticastLock)   │
│   ├── TCP server on port 45782 (HMAC verify + nonce + ts drift check)   │
│   ├── NWBrowser equivalent: NsdManager advertise _snapback._tcp.local   │
│   ├── AccessibilityService: performGlobalAction(LOCK_SCREEN) — primary  │
│   ├── DevicePolicyManager.lockNow() — fallback when Device Admin enabled│
│   ├── ScreenStateGate: isInteractive && !isDeviceLocked                 │
│   ├── HOLD state machine (§5.4)                                          │
│   └── Resync handshake on any (re)connect (§5.5)                         │
│                                                                          │
│  PairingActivity  — CameraX + ML Kit QR scanner                         │
│  SettingsActivity — enable/disable, history log, unpair, OEM onboard    │
└──────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Why the bridge is a daemon, not a spawn-per-hook

Claude hooks run on the hot path of the agent loop. A fresh process per event (launch + TCP handshake + send + teardown) costs 100–300 ms and would be visible as slower Claude responsiveness. The bridge keeps one process alive with a persistent TCP connection, so the hook's only work is writing one framed message to a Unix-domain socket and exiting.

**Honest latency budget:**

- Hook calls `snapback-poke attention` in the background (`&`). Parent hook process returns in ~1 ms (fork cost).
- The `snapback-poke` child takes ~2–4 ms wall time: connect to UDS, write framed bytes, close.
- This is the **bridge-present** hot path. The `nc` path considered in v0 of this spec had 8–25 ms wall time due to `nc` fork+exec and, without `-N`, leaked processes. That approach was rejected.
- **Bridge-absent** path: `[ -S $SOCKET ]` short-circuits before forking. Measured ~0.3 ms.
- Test gate: `tests/latency.bats` asserts *both* cases: parent-hook ≤10 ms bridge-absent, ≤20 ms bridge-present on a warm Mac. Both measured as the time `snapback.sh` takes to return from Claude's perspective.

### 3.2 Why the bridge lives inside SnapBackApp

- The Swift codebase already exists and already runs in the background as a menu-bar app.
- Status visibility (🟢/🟡/🔴/⚫) naturally lives in the menu-bar UI.
- One process = one code path for config, Keychain access, UI.
- "If SnapBackApp is not running, the mobile feature is off" is a clear, legible contract. Users who want persistence can add a launchd agent in v2.

### 3.3 Why LAN / mDNS, not cloud push

- No backend means no ongoing cost, no account system, no TOS, no privacy footprint.
- Latency on LAN is <50 ms; cloud push would be 500–2000 ms.
- Target use case (user at their desk, phone next to them) is always co-located on the same LAN.

(Cloud relay is explicitly a non-goal for this spec — see §1.)

## 4. Wire protocol

### 4.1 Message format (JSON)

```json
{
  "v": 1,
  "type": "hello" | "attention" | "resume" | "heartbeat" | "ack" | "pong" | "invalidate" | "resync",
  "ts": 1734556677,
  "nonce": "4a7b1c...",
  "payload": {},
  "hmac": "9c3e..."
}
```

Messages are framed as one JSON object per line, UTF-8, delimited by `\n`. The sender's writes are newline-terminated; the receiver reads line by line.

**Field rules (no ambiguity):**

- `v` — protocol version. Integer. Receiver rejects unknown versions.
- `type` — event type string from the fixed set above.
- `ts` — unix seconds at sender. Integer. Receiver rejects if `|receiver_ts - ts| > 30`.
- `nonce` — exactly 32 hex characters (16 random bytes). Receiver caches seen nonces **per shared-secret** (effectively global in MVP, one secret) for 10 min.
- `payload` — object. When absent, serialized as literal `{}` (never omitted, never `null`). For the initial protocol:
  - `attention` carries `{"hook": "PermissionRequest" | "Stop"}` so the phone can distinguish a mid-task permission ask from end-of-task blocking.
  - `resume`, `heartbeat`, `pong`, `ack`, `invalidate`, `resync` carry `{}`.
  - `hello` carries `{"peer_name": "<printable>", "app_version": "1.3.0"}`.
- `hmac` — HMAC-SHA256, hex-encoded, over the signing domain described below.

**Signing domain (explicit, no "canonical JSON" argument):**

```
HMAC-SHA256( secret,
    dir || "\x00" ||            // "c2s" or "s2c", ASCII, null-terminated
    ascii(v) || "\x00" ||       // decimal ASCII, no leading zeros
    type || "\x00" ||           // lowercase ASCII
    ascii(ts) || "\x00" ||      // decimal ASCII, no leading zeros
    nonce || "\x00" ||          // 32 hex chars, lowercase
    payload_bytes               // payload JSON serialized with RFC-8785-style canonicalization
)
```

- `dir = "c2s"` for Mac→Phone, `"s2c"` for Phone→Mac. A direction byte prevents a LAN attacker from reflecting a Mac→Phone `hello` back to the Mac and having it verify.
- `payload_bytes` is the payload object serialized with: sorted object keys, UTF-8, numbers as shortest decimal, no whitespace, strings with minimal JSON escaping (only `\\`, `\"`, `\n`, `\r`, `\t`, `\b`, `\f`, `\uXXXX` for control chars). Empty payload is literal `{}` (two bytes).
- Signed bytes are concatenated with null separators (`\x00`) so two different field values cannot produce the same signing input.
- The `hmac` field itself is **not** part of the signing domain. Framing bytes (newlines) are **not** signed.
- Both sides ship identical test vectors in their test suites (`tests/protocol-vectors.json`) to catch divergent implementations.

**Replay and drift invariant:**

- Nonce TTL (10 min) > ts window (30 s) + generous clock-skew budget. This invariant is stated so future edits can't narrow the nonce cache without also tightening the ts window.

### 4.2 Event types

| Type | Direction | Semantics |
|---|---|---|
| `hello` | Mac → Phone | First message after TCP connect; phone replies `ack`. Establishes session. Payload carries `peer_name` and `app_version`. |
| `ack` | Phone → Mac | Acknowledgement of `hello`. |
| `attention` | Mac → Phone | Claude entered waiting state. Phone evaluates gate + enters HOLD. Payload: `{"hook":"PermissionRequest"|"Stop"}`. |
| `resume` | Mac → Phone | Claude resumed work (user sent prompt). Phone exits HOLD. |
| `heartbeat` | Mac → Phone | Sent every 30 s while a HOLD is live. Confirms Mac is alive. |
| `pong` | Phone → Mac | Reply to `heartbeat`. Phone includes current HOLD state in payload: `{"hold": true|false}`. |
| `resync` | Mac → Phone | On every (re)connect after pairing, Mac sends `resync` to ask phone for its current HOLD state. Phone replies with a `pong`-shaped payload. Prevents stale state after Mac sleep, WiFi change, phone reboot. |
| `invalidate` | Mac → Phone | Best-effort notice on unpair. Signed with the **pre-deletion** token. Phone wipes its token on receipt. Undelivered is fine: the HMAC-mismatch path converges eventually. |

### 4.3 Pairing

1. User clicks "Pair mobile" in the menu-bar app.
2. SnapBackApp generates a 32-byte random token; stores it in macOS Keychain (`service="com.snapback.mobile"`, `account="pair-token"`) with ACL `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — does **not** iCloud-sync.
3. SnapBackApp displays a QR code encoding: `snapback-pair://v1?token=<hex>&desk=<URL-encoded MacName>&v=1`. `MacName` is `Host.current().localizedName ?? "Mac"`; URL-encoded so spaces/emoji are safe.
4. User opens SnapBack Mobile → Pair → scans QR. App stores the token in Android Keystore (alias `com.snapback.mobile.token`, hardware-backed where available).
5. Android app starts its foreground service and begins advertising `_snapback._tcp.local` on port 45782. TXT record is purely cosmetic (`device_name=<Build.MODEL>`); the Mac does not treat it as load-bearing.
6. Desktop bridge — via `NWBrowser` subscribed to `_snapback._tcp.local` — resolves the service, opens TCP, sends `hello`. Phone verifies HMAC and sends `ack`.
7. Pair complete. Both sides persist each other's identity.

### 4.4 Unpairing

- `snapback mobile unpair` on Mac: attempts to send `invalidate` using the current token first, then deletes the Keychain token, then marks local state as unpaired. If the `invalidate` send fails, proceed anyway — the phone's HMAC-mismatch rate-limit (§6) handles it.
- "Unpair" in Android settings: wipes token from Android Keystore, stops foreground service, stops mDNS advertising.
- If only one side unpairs, the other side eventually rate-limits then goes quiet.

## 5. Components

### 5.1 Hook script changes (`snapback.sh`, `snapback-resume.sh`)

Append one line to each:

```bash
# snapback.sh (after existing sound + focus logic)
[ -S "$SNAPBACK_BRIDGE_SOCKET" ] && \
  snapback-poke attention PermissionRequest >/dev/null 2>&1 &

# snapback-resume.sh (after existing resume logic)
[ -S "$SNAPBACK_BRIDGE_SOCKET" ] && \
  snapback-poke resume >/dev/null 2>&1 &
```

`SNAPBACK_BRIDGE_SOCKET` defaults to `${TMPDIR:-/tmp}/snapback-bridge.sock` (exported by `snapback-lib.sh`). `$TMPDIR` on macOS is per-user, which avoids multi-user collisions and keeps alignment with existing SnapBack paths.

`snapback-poke` is a small compiled helper (C or Swift, ~40 lines) shipped with SnapBackApp into `/usr/local/bin/` by the installer:

```c
// snapback-poke <type> [hook_kind]
// Opens SNAPBACK_BRIDGE_SOCKET, writes "<type>[\t<hook_kind>]\n", closes, exits.
// Total wall time: 2–4 ms when socket is accepting.
```

This avoids `nc`'s fragility (lingering FDs without `-N`) and avoids a fork+exec of `/usr/bin/nc`. Behaviour on missing socket or refused connection: exit 0 silently. The hook must never fail or block because of the bridge.

### 5.2 Bridge daemon (`SnapBackApp/Sources/Bridge/`)

Swift, using `Network.framework` end-to-end (no `NetService`). Path everywhere: `${TMPDIR:-/tmp}/snapback-bridge.sock`.

- `BridgeServer` — `NWListener` on a Unix-domain socket. Parses TSV-ish lines (`type\thook_kind?\n`).
- `MobilePeer` — wraps an `NWConnection` to the phone. Reconnects with exponential backoff (0.5 → 2 → 8 → 30 → 120 s capped). Emits status events.
- `MDNSBrowser` — `NWBrowser` on `_snapback._tcp.local`. Re-armed on `NWPathMonitor` updates (SSID/interface change) so docking/roaming recovers automatically.
- `MessageCodec` — JSON encode/decode + HMAC sign/verify per §4.1. Token fetched from Keychain once per session, cached in memory.
- `NonceCache` — LRU of nonces seen from the phone (10 min TTL). Used only on the receive path.
- `EventQueue` — bounded queue (max 16). Retries `attention`/`resume` with 0.5 s / 2 s / 8 s backoff; drops after 3 failures and logs. Heartbeats are not queued (fire-and-forget; missed heartbeats are the signal).
- `HeartbeatLoop` — while `hold_outstanding == true`, pings phone every 30 s starting 30 s after HOLD entry (not immediately). Two consecutive missed `pong`s → mark phone unreachable and local-side `hold_outstanding = false`.
- `ResyncOnReconnect` — every time `MobilePeer` transitions `connecting → connected` after pairing, send `hello` then immediately `resync`. Use the phone's reply to update `hold_outstanding`.
- `StatusPublisher` — exposes `connected | unreachable | error | unpaired` to the SnapBackApp UI via Combine.
- `BridgeLog` — rolling file log at `~/Library/Logs/SnapBack/bridge.log`, 1 MB × 5 rotation.

### 5.3 SnapBack Mobile (Android, Kotlin) — 1.4.0

New Gradle project under `SnapBackMobile/` (sibling directory; separate signing key and `applicationId`).

#### 5.3.1 Components

- `MobileForegroundService` — persistent notification "SnapBack active". Owns the server socket lifecycle. Acquires a `WifiManager.MulticastLock` for the service's lifetime and a `WifiManager.WifiLock(WIFI_MODE_FULL_HIGH_PERF)` **only while `hold_outstanding == true`** (not permanently — that kills battery).
- `MessageServer` — coroutine TCP listener on `45782`. Authenticates via HMAC; rejects stale ts (>30 s) or replayed nonces. Backpressure: after 10 bad-HMAC connections from one IP in 60 s, adds IP to a 5-min deny list; logs but does not auto-unpair. No remote kill switch.
- `NonceCache` — LRU of recent nonces (10 min TTL, per-secret).
- `HoldStateMachine` — §5.4.
- `ScreenStateGate` — reads `PowerManager.isInteractive` && `!KeyguardManager.isDeviceLocked`. **Foreground-app is not part of the gate.** Previous draft included it; review flagged that Accessibility-based foreground detection adds Play policy risk for no additional value over `isInteractive + !isDeviceLocked`.
- `LockDriver` — issues the lock. Tries, in order:
  1. `performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)` via the registered AccessibilityService.
  2. If Accessibility disabled and Device Admin enabled: `DevicePolicyManager.lockNow()`.
  3. Otherwise: fullscreen Activity overlay (weakest; the spec accepts its limits).
- `AccessibilitySupportService` — an `AccessibilityService` whose **sole declared purpose** is `performGlobalAction` for lock, via `accessibility_service_config.xml` with `canPerformGestures="false"` and `accessibilityEventTypes="none"`. We do **not** subscribe to `TYPE_WINDOW_STATE_CHANGED`. This stays inside the Accessibility primitives' on-label use.
- `DeviceAdminReceiver` — optional; users who want stricter lock can enable it. Not required for core function.
- `MDnsAdvertiser` — `NsdManager.registerService` for `_snapback._tcp.local`. Auto re-registers on `CONNECTIVITY_ACTION` changes.
- `PairingActivity` — CameraX + ML Kit QR scanner. Single activity, discarded after use.
- `SettingsActivity` — toggle enable/disable, unpair, OEM onboarding card (§5.8), show last 50 events from a Room DB, battery-impact sheet.

#### 5.3.2 Why Accessibility-primary, Device-Admin-fallback

- Device Admin `lockNow()` is a supported API on Android 14/15/16, but Google Play policy (since 2023, tightened 2024) rejects non-enterprise apps that use it as a primary mechanism. SnapBack's use is consumer-focused.
- `GLOBAL_ACTION_LOCK_SCREEN` (API 28+) is the policy-safe primitive for this exact use case. It locks the device immediately. No Device Admin needed.
- Accessibility still has policy friction of its own, but reading no events and only performing one global action for a clearly-disclosed lock behaviour is within the on-label use pattern.
- Since 1.4.0 is sideload-only (§8.2), Play policy isn't directly blocking, but the *user's* permission UX matters: Accessibility has one opt-in screen; Device Admin has one scarier one. Accessibility-first is better onboarding even sideloaded.
- Device Admin remains as a fallback for users who specifically want `lockNow` semantics or whose OEM has weird Accessibility behaviour.

### 5.4 HOLD state machine and fail-safes

```
                ┌──────────┐
                │   IDLE   │ ◀─── (resume) ∨ (hard timeout 10m)
                └────┬─────┘        ∨ (2 missed heartbeats ≈ 60 s)
                     │               ∨ (manual release — Settings)
                     │ attention ∧ gate passes
                     ▼
                ┌──────────┐
                │   HOLD   │ ─── on ACTION_USER_PRESENT → lockDriver.lock()
                └──────────┘        after 250 ms grace
```

**Fail-safes:**

- **Hard timeout**: phone exits HOLD 10 min after entering, regardless of Mac activity. 10-min TTL is implicit on the phone's state machine, not a TTL field in the message.
- **Heartbeat**: missing two consecutive 30 s heartbeats (~60–65 s silence) exits HOLD. Mac closing its laptop lid is the common trigger: heartbeats stop, phone releases in ≤65 s.
- **Manual release**: settings screen has "Release hold" (long press 3 s).
- **Phone reboot**: HOLD is in-memory; phone reboots into IDLE. On next connect, `resync` brings the Mac back in sync (§4.2).
- **Device Admin revoked mid-HOLD**: `LockDriver` falls back to Accessibility automatically; if Accessibility also denied, fullscreen overlay; phone does **not** exit HOLD on permission changes.
- **Re-lock grace**: 250 ms (down from 1 s). On unlock, lock re-fires before user can open a video. Too-short values risk unlock-storm bugs; 250 ms is empirical from similar focus apps. Configurable in `debug` builds only.

### 5.5 Status surfaces on Mac

| Surface | What it shows | When it updates |
|---|---|---|
| Menu-bar dot | 🟢 connected / 🟡 unreachable / 🔴 error / ⚫ unpaired | On any state change. |
| macOS user notification | "SnapBack: mobile unreachable" / "SnapBack: mobile reconnected" | **Only on state transition**, never on steady state. Rate-limited to 1/min. |
| `snapback mobile status` | Peer name, last event time, queue depth, last error, HOLD state as of last `pong` | On demand. |
| `snapback mobile logs` | Tail of `~/Library/Logs/SnapBack/bridge.log` | On demand. |

### 5.6 Config surface

#### 5.6.1 Known-keys table diff in `snapback-lib.sh`

Existing known-keys table gets two rows added (one commit alongside bridge rollout):

```bash
# snapback-lib.sh — KNOWN_KEYS additions
# Format: KEY|type  (per unification spec §4.1)

MOBILE_ENABLED|scalar           # "true" | "false". Default "false".
MOBILE_DEVICE_NAME|scalar       # informational; set by bridge after pair.
```

Without this diff, `snapback mobile enable` would need `--allow-new`, which is a code smell. The diff is a required part of the 1.3.0 plan, not an afterthought.

Secrets (the 32-byte pair token) live in the macOS Keychain, **not** the config file.

#### 5.6.2 CLI subcommands

- `snapback mobile pair` — launches SnapBackApp pairing UI.
- `snapback mobile unpair` — attempts `invalidate`, then wipes token, then sets `MOBILE_ENABLED=false`.
- `snapback mobile status` — prints peer, state, queue, last error, last HOLD-state.
- `snapback mobile logs` — tails bridge log.
- `snapback mobile enable | disable` — flips `MOBILE_ENABLED` via `config_set`.

#### 5.6.3 Uninstall hygiene

`snapback uninstall` deletes the Keychain entry (`service="com.snapback.mobile"`) in addition to its existing cleanup.

### 5.7 Forward compatibility with N:M

Message format has a `v` field; every component validates it. Pair token is per-peer, so storing multiple tokens is a straightforward extension:

- Desktop Keychain: one token entry per paired phone.
- Phone Keystore: one token entry per paired desk.
- `hello` carries sender identity (`peer_name` today is display-only; a future `peer_id` field is the identifier for routing).

MVP hard-codes one token each way and rejects a second pair attempt on the **Mac side** with "this Mac is already paired. Unpair first." The phone has no symmetric warning; if a second Mac pair happens, the newer token replaces the older on the phone. This is asymmetric and documented.

### 5.8 OEM quirks and onboarding

Samsung (One UI 6+), Xiaomi (MIUI 14+), OnePlus, Huawei aggressively kill foreground services and suspend `NsdManager` after screen-off. Mitigations:

- **Persistent**: hold `MulticastLock` for the lifetime of the foreground service; hold `WifiLock(HIGH_PERF)` only during HOLD.
- **Onboarding**: on first launch and after each major OS update, the Settings screen shows an OEM-specific card:
  - Samsung: walk the user through `Settings → Apps → SnapBack Mobile → Battery → Unrestricted`.
  - Xiaomi: `Settings → Apps → SnapBack Mobile → Battery saver → No restrictions` + `Autostart → enabled`.
  - OnePlus: similar to Samsung.
  - Other/unknown: generic "disable battery optimisation" deeplink via `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- **Self-test**: Settings has a "Test lock" button that triggers the full path (fake attention → gate → lock) so users verify post-onboarding.
- **Observability**: battery-impact sheet shows service uptime and lock count for last 24 h.

### 5.9 Distribution

- **1.3.0 bridge**: ships as part of the existing SnapBack installer (`get.sh`, `snapback update`, built menu-bar app). `snapback-poke` installed via the menu-bar app's install path alongside `snapback.app`.
- **1.4.0 Android app**: GitHub Releases APK, signed with a project-specific keystore (kept in project secrets). Installation: sideload after enabling "Install from unknown sources" for GitHub. README will spell this out and cross-link to the signing-key fingerprint for users who verify.
- **Play Store**: deliberately out of scope for 1.4.0. A future spec evaluates the review cost (Accessibility justification, Device Admin removal) against the user-install friction reduction.

## 6. Error handling summary

| Situation | Behaviour |
|---|---|
| Bridge daemon down | `snapback-poke` exits silently; hook returns in ~1 ms. Sound + focus unaffected. |
| Phone unreachable | Event enqueued; retry 0.5 s / 2 s / 8 s, then dropped. Menu-bar transitions 🟢→🟡→🔴. User notified once on first transition. |
| HMAC mismatch (either side) | Message logged and dropped. No auto-unpair. IP-level rate-limit on the phone after 10 mismatches from one IP in 60 s; Mac simply logs and keeps retrying. (Earlier draft auto-unpaired after 5 — that was a remote kill switch for any LAN attacker; removed.) |
| Replay (seen nonce) | Dropped silently. |
| Clock skew | Tolerated within ±30 s; NTP normally keeps skew <1 s. |
| Mac closes lid during HOLD | TCP goes half-open; heartbeats stop; phone exits HOLD after ~65 s. On lid-open, bridge reconnects, `hello` + `resync` fetches current phone state. If Mac thinks HOLD is still outstanding it is corrected to the phone's ground truth. |
| WiFi SSID change / docking | `NWPathMonitor` observed by `MDNSBrowser`; bridge re-arms mDNS browse on change. Reconnect triggers `resync`. |
| Phone reboots mid-HOLD | Phone comes back IDLE; reconnect + `resync` realigns state. No user-visible glitch beyond the reboot itself. |
| Device Admin revoked during HOLD | `LockDriver` falls back to Accessibility. HOLD state unaffected. |
| Accessibility revoked during HOLD | `LockDriver` falls back to Device Admin (if enabled) or overlay. HOLD state unaffected. |
| Duplicate pair attempt (MVP) | Desktop shows "this Mac is already paired. Unpair first." (not "paired to X" — the desktop only knows its own state.) |
| Mac sandbox adopted later | UDS path moves to `~/Library/Containers/<id>/Data/tmp/snapback-bridge.sock`; `SNAPBACK_BRIDGE_SOCKET` env var mechanism already supports this. |

## 7. Testing strategy

| Layer | Scope | Tooling |
|---|---|---|
| Bridge unit | HMAC sign/verify (including test vectors from `tests/protocol-vectors.json`), nonce cache, retry/backoff, codec round-trip, resync round-trip | Swift XCTest |
| Bridge integration | UDS receive, in-process fake phone peer, reconnect after simulated network loss, `NWPathMonitor` change simulation | Swift XCTest + loopback `NWListener` |
| `snapback-poke` | Exit codes, socket-missing behaviour, socket-refused behaviour, CLI argument parsing | bash + bats |
| Android unit | Message parse, HMAC verify (same `tests/protocol-vectors.json`), HOLD state machine transitions, nonce cache, gate logic | Kotlin JUnit + Robolectric |
| Android instrumented | `performGlobalAction(LOCK_SCREEN)`, fallback to Device Admin, re-lock loop timing, `NsdManager` registration | Espresso + emulator |
| End-to-end | Hook shell invocation → bridge → emulator lock screen observed | CI script: boot emulator, build bridge, trigger hook, assert `dumpsys power` state |
| Hook latency regression | `snapback.sh` under 10 ms absent-bridge, under 20 ms present-bridge | `tests/latency.bats` (new) — runs both scenarios |
| Protocol conformance | Both sides decode identical `tests/protocol-vectors.json` and produce identical signatures | Shared vector fixture; run in both test suites |
| Existing bats | All current SnapBack tests still pass unchanged | `bats tests/` |

## 8. Rollout plan

Split into two versions. Each gets its own implementation plan.

### 8.1 Version 1.3.0 — Desktop bridge only (shippable alone)

Target: everything in §5.1, §5.2, §5.5, §5.6, §5.7, §5.9 (first bullet). **No phone app.**

1. Add `MOBILE_ENABLED`, `MOBILE_DEVICE_NAME` to `snapback-lib.sh` known-keys table (§5.6.1).
2. Implement `snapback-poke` helper; install into SnapBackApp's install path; add hook-line changes to `snapback.sh` / `snapback-resume.sh` behind the `[ -S ... ]` precheck.
3. Bridge daemon in `SnapBackApp/Sources/Bridge/` using `Network.framework` end-to-end. UDS listener + event queue + JSON codec + HMAC (matching §4.1, including direction byte and test vectors).
4. Status surface in menu-bar (dot + "Mobile" tab placeholder with pair-UI and "no peer paired" message).
5. Pairing UI: QR generation, Keychain write, `NWBrowser` start.
6. Resync and heartbeat logic even though there is no phone to exchange them with — written against a test fake to freeze the protocol.
7. `snapback mobile pair/unpair/status/logs/enable/disable` CLI.
8. Tests: bridge unit, integration, `snapback-poke`, latency bats, protocol vectors.
9. Docs: `docs/PROTOCOL.md` froze; README updated.
10. Release 1.3.0.

At this point 1.3.0 is a standalone "mobile-ready" release. Users see a menu-bar affordance that says "pair a phone" and the pair flow generates a QR that no app can yet scan — but the protocol, tests, and UI are real.

### 8.2 Version 1.4.0 — Android companion

Target: everything in §5.3, §5.4, §5.8, §5.9 (second bullet).

1. New Gradle project `SnapBackMobile/`. Minimum SDK API 30 (Android 11), target API 36 (Android 16).
2. Pairing: CameraX + ML Kit QR scanner → Android Keystore.
3. Foreground service + `NsdManager` advertiser + `MulticastLock` + WifiLock-during-HOLD.
4. `MessageServer` with HMAC/nonce/ts verification against shared test vectors.
5. Accessibility service registration + `LockDriver` (Accessibility primary, Device Admin fallback, overlay last).
6. `HoldStateMachine`, `ScreenStateGate`, `ACTION_USER_PRESENT` re-lock.
7. Settings: enable/disable, unpair, Room-backed event log (last 50), battery-impact sheet.
8. OEM onboarding cards for Samsung, Xiaomi, OnePlus, generic.
9. Tests: Kotlin unit (including shared test vectors), instrumented on emulator, end-to-end with a real Mac bridge.
10. Release build + signing keystore + GitHub Releases APK.
11. README for the companion with per-OEM setup and "Test lock" verification step.
12. Release 1.4.0.

Play-store submission and iOS are explicit follow-ups, each their own spec.

## 9. What this does not change

- `snapback.sh` remains the source of truth for desktop attention behaviour.
- Existing config keys, hooks, and CLI commands are untouched.
- Menu-bar app keeps its current surface; "Mobile" is a new tab, not a replacement.
- `get.sh` and `snapback update` keep working.
- No backend, no account, no telemetry.
- SnapBackApp remains unsandboxed in 1.3.0; sandbox adoption is a separate, later decision with known migration path (§6 last row).
