# SnapBack Mobile Companion — Design

Date: 2026-04-18
Status: Awaiting user approval
Target version: 1.3.0 (new minor — introduces mobile tier)

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

- iOS support. iOS lacks the Device Admin primitives this design depends on; a separate spec is required if/when we address it.
- Remote (off-LAN) operation. "Phone on cellular data while Mac is on WiFi" is explicitly out of scope for MVP. Follow-up spec could add a cloud relay.
- Multi-device (N:M). MVP is 1 phone ↔ 1 Mac. Protocol leaves room for extension (§5.7).
- Displaying Claude's prompt content on the phone. Lock screen shows only that *something* is waiting — no prompt text.
- A Claude Code client on the phone. Claude runs on the Mac; the phone only participates in the attention loop.

## 2. Design decisions (resolved during brainstorming)

| Question | Decision | Rationale |
|---|---|---|
| User scenario | Anti-distraction (user at PC, drifts to phone) | Matches the user's stated pain. |
| Intervention level | Hard force lock via Device Admin `lockNow()` | User explicitly chose "turn screen off or similar". |
| Trigger gate | Only when phone screen is on *and* unlocked | Phone in pocket = no-op. Quieter, less battery drain. |
| Transport | LAN / mDNS with HMAC-SHA256 over plain TCP | No backend, no accounts, fits SnapBack philosophy. Confidentiality unnecessary (no sensitive payload). |
| Platform (MVP) | Android only | Has Device Admin, Accessibility, foreground services. iOS cannot implement this cleanly. |
| Release condition | Auto-unlock only when Claude resume hook fires | Strongest accountability; poistky handle bugs (§5.4). |
| Pairing | QR code with 32-byte shared secret | Simple, offline, secure enough for LAN. |
| Device cardinality | 1 phone ↔ 1 Mac for MVP | Smallest footprint. Protocol forward-compatible with N:M. |
| Emergency PIN on phone | Not included | User declined; manual override in app is sufficient. |
| Bridge process model | Long-running daemon inside SnapBackApp | Hook scripts do only a Unix-socket write (≤5 ms). No hook latency regression. |
| Auto-restart (launchd) | v2, not MVP | "App is running = mobile is connected" is an acceptable MVP contract; menu-bar dot exposes state. |

## 3. Architecture

```
┌────────────────── Mac (SnapBack existujúce + Bridge) ───────────────────┐
│                                                                          │
│  Claude Code ──hooks──▶ snapback.sh  ──▶ sound + focus (unchanged)      │
│                              │                                           │
│                              └──▶ echo "attention" > /tmp/snapback-     │
│                                   bridge.sock  &    (fire-and-forget)    │
│                                          │                               │
│                                          ▼                               │
│                         ┌─────────── Bridge daemon ───────────┐         │
│                         │  (Swift, lives inside SnapBackApp)  │         │
│                         │  • Unix socket listener             │         │
│                         │  • mDNS browse _snapback._tcp       │         │
│                         │  • persistent TCP + heartbeat       │         │
│                         │  • HMAC sign; nonce + ts            │         │
│                         │  • event queue + retry/backoff      │         │
│                         │  • publishes status to menu-bar UI  │         │
│                         │  • rolling log to ~/Library/Logs/   │         │
│                         └──────────────────┬──────────────────┘         │
│                                            │                             │
│  Claude Code ──UserPromptSubmit──▶ snapback-resume.sh ──▶ "resume"     │
└────────────────────────────────────────────┼─────────────────────────────┘
                                             │ TCP + HMAC, LAN-only
                                             ▼
┌──────────────────── Android (SnapBack Mobile) ──────────────────────────┐
│                                                                          │
│  ForegroundService (persistent notification)                             │
│   ├── TLS-less TCP server on port 45782                                  │
│   ├── HMAC verify + nonce cache + ts drift check                         │
│   ├── AccessibilityService: screen_on? unlocked? fg app?                 │
│   ├── DevicePolicyManager.lockNow()  — on "attention"                   │
│   ├── HOLD state machine (§5.4)                                          │
│   └── mDNS advertise _snapback._tcp.local                                │
│                                                                          │
│  PairingActivity   — CameraX + ML Kit QR scanner                        │
│  SettingsActivity  — enable/disable, history log, unpair                │
└──────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Why the bridge is a daemon, not a spawn-per-hook

Each Claude hook blocks the agent loop. A fresh process per event (launch + TCP handshake + send + teardown) costs 100–300 ms and would be visible as slower Claude responsiveness. By keeping one process alive with a persistent TCP connection, the hook's only work is a single `write()` to a Unix socket, measured in microseconds. The bridge handles network reality asynchronously.

### 3.2 Why the bridge lives inside SnapBackApp

- The Swift codebase already exists and already runs in the background as a menu-bar app.
- Status visibility (🟢/🟡/🔴/⚫) naturally lives in the menu-bar UI.
- One process = one code path for config, Keychain access, UI.
- "If SnapBackApp is not running, the mobile feature is off" is a clear, legible contract. Users who want persistence can add a launchd agent in v2.

### 3.3 Why LAN / mDNS, not cloud push

- No backend means no ongoing cost, no account system, no TOS, no privacy footprint.
- Latency on LAN is <50 ms; cloud push would be 500–2000 ms.
- Target use case (user at their desk, phone next to them) is always co-located on the same LAN.
- Cloud relay can be added later as fallback without changing message format.

## 4. Wire protocol

### 4.1 Message format (JSON)

```json
{
  "v": 1,
  "type": "hello" | "attention" | "resume" | "heartbeat" | "ack" | "pong",
  "ts": 1734556677,
  "nonce": "4a7b1c...",
  "payload": {},
  "hmac": "9c3e..."
}
```

- `v` — protocol version. Receiver rejects unknown versions.
- `type` — event type (see §4.2).
- `ts` — unix seconds at sender. Receiver rejects if `|receiver_ts - ts| > 30`.
- `nonce` — 16 random bytes (hex-encoded). Receiver caches seen nonces **per peer** for 10 min and rejects duplicates.
- `payload` — optional type-specific fields. Empty for MVP; encoded as `{}` when absent.
- `hmac` — HMAC-SHA256, hex-encoded, over the byte string `v|type|ts|nonce|payload_json`, where `payload_json` is the JSON serialization of `payload` with sorted object keys, UTF-8, no whitespace. The token is the 32-byte shared secret from pairing.

Messages are framed as one JSON object per line, UTF-8, delimited by `\n`.

The HMAC domain deliberately excludes the `hmac` field itself and any framing bytes. Both sides use the same serialization rule so signatures are reproducible.

### 4.2 Event types

| Type | Direction | Semantics |
|---|---|---|
| `hello` | Mac → Phone | First message after TCP connect; phone replies `ack`. Establishes session. |
| `ack` | Phone → Mac | Acknowledgement of `hello`. |
| `attention` | Mac → Phone | Claude entered waiting state. Phone evaluates gate + enters HOLD. |
| `resume` | Mac → Phone | Claude resumed work (user sent prompt). Phone exits HOLD. |
| `heartbeat` | Mac → Phone | Sent every 30 s while in HOLD. Confirms Mac is alive. |
| `pong` | Phone → Mac | Reply to `heartbeat`. |
| `invalidate` | Mac → Phone | Best-effort notice on unpair. Phone wipes its token. If not delivered, normal HMAC-mismatch path (§6) handles eventually. |

### 4.3 Pairing

1. User clicks "Pair mobile" in the menu-bar app.
2. SnapBackApp generates a 32-byte random token, stores it in macOS Keychain under `com.snapback.mobile.token`.
3. SnapBackApp displays a QR code encoding: `snapback-pair://v1?token=<hex>&desk=<MacName>`.
4. User opens SnapBack Mobile → Pair → scans QR. App stores the token in Android Keystore.
5. Android app starts its foreground service and begins advertising `_snapback._tcp.local` on port 45782 with TXT record `device_name=<model>`.
6. Desktop bridge (on next tick) resolves the mDNS service, opens TCP, sends `hello`. Phone verifies HMAC and sends `ack`.
7. Pair complete. Both sides persist each other's identity.

### 4.4 Unpairing

- `snapback mobile unpair` on Mac: deletes Keychain token, sends best-effort `invalidate` message (new type, v1 extension) to phone, marks local state as unpaired.
- "Unpair" in Android settings: wipes token from Android Keystore, stops foreground service, stops mDNS advertising.
- If only one side unpairs, the other side eventually sees HMAC mismatch → degrades to unpaired.

## 5. Components

### 5.1 Hook script changes (`snapback.sh`, `snapback-resume.sh`)

Append one line to each:

```bash
# snapback.sh (after existing sound + focus logic)
[ -S /tmp/snapback-bridge.sock ] && \
  ( printf 'attention\n' | nc -U /tmp/snapback-bridge.sock >/dev/null 2>&1 ) &
```

```bash
# snapback-resume.sh (after existing resume logic)
[ -S /tmp/snapback-bridge.sock ] && \
  ( printf 'resume\n' | nc -U /tmp/snapback-bridge.sock >/dev/null 2>&1 ) &
```

Fails silently if bridge is not running. The subshell + `&` makes the whole thing fire-and-forget — the parent hook returns immediately regardless of `nc`'s behaviour. The socket-exists precheck avoids even forking when the feature is off.

### 5.2 Bridge daemon (`SnapBackApp/Sources/Bridge/`)

Swift, using `Network.framework` and `NetService` for mDNS:

- `BridgeServer` — Unix socket listener on `/tmp/snapback-bridge.sock`. Parses newline-delimited events.
- `MobilePeer` — wraps the persistent TCP connection to the phone. Reconnects with backoff. Emits status events.
- `MessageCodec` — JSON encode/decode + HMAC-SHA256 sign/verify. Token fetched from Keychain.
- `EventQueue` — bounded queue (max 16). Retries `attention`/`resume` with 0.5 s / 2 s / 8 s backoff; drops after 3 failures and logs.
- `HeartbeatLoop` — while a pending HOLD is outstanding, pings phone every 30 s.
- `StatusPublisher` — exposes `connected | unreachable | error | unpaired` to the SnapBackApp UI via Combine.
- `BridgeLog` — rolling file log at `~/Library/Logs/SnapBack/bridge.log`, 1 MB × 5 rotation.

### 5.3 SnapBack Mobile (Android, Kotlin)

New Gradle project under `SnapBackMobile/`:

- `MobileForegroundService` — persistent notification "SnapBack active". Owns the server socket lifecycle.
- `MessageServer` — coroutine-based TCP listener on the default port 45782 (constant, configurable in a later version if needed). Authenticates via HMAC; rejects stale ts (>30 s) or replayed nonces.
- `NonceCache` — LRU of recent nonces (10 min TTL).
- `HoldStateMachine` — enters HOLD on `attention`, exits on `resume`, on heartbeat timeout, or on hard 10-min timeout. While HOLD is active, observes unlock events and re-issues `lockNow` after a 1 s grace.
- `ScreenStateGate` — reads `PowerManager.isInteractive` + `KeyguardManager.isDeviceLocked` + Accessibility foreground-app to decide whether an `attention` event is actionable.
- `DeviceAdminReceiver` — registered receiver enabling `lockNow()`.
- `AccessibilitySupportService` — subscribes to `TYPE_WINDOW_STATE_CHANGED` only; minimal scope.
- `MDnsAdvertiser` — uses `NsdManager` to publish `_snapback._tcp.local`.
- `PairingActivity` — CameraX + ML Kit QR scanner.
- `SettingsActivity` — toggle enable/disable, unpair, show last 50 events from a Room DB.

### 5.4 HOLD state machine and fail-safes

```
                ┌──────────┐
                │   IDLE   │ ◀───── (resume) OR (hard timeout 10m)
                └────┬─────┘        OR (2 missed heartbeats)
                     │ attention && gate passes
                     ▼
                ┌──────────┐
                │   HOLD   │ ── on user_present event → lockNow again after 1 s
                └──────────┘
```

Fail-safes (all inherent to the state machine, no user action):

- **Hard timeout**: `attention` carries an effective 10-min TTL. Phone exits HOLD even with no `resume`.
- **Heartbeat**: if the phone misses 2 consecutive 30 s heartbeats (desktop dead), HOLD exits.
- **Manual release**: settings screen has "Release hold" (long press 3 s).
- **Degraded permissions**: if Device Admin is denied, the app falls back to a fullscreen activity overlay (weaker, dismissible with back-button + home). If Accessibility is denied, the gate is skipped — locks always apply when `attention` arrives.

### 5.5 Status surfaces on Mac

| Surface | What it shows | When it updates |
|---|---|---|
| Menu-bar dot | 🟢 connected / 🟡 unreachable / 🔴 error / ⚫ unpaired | On any state change. |
| macOS user notification | "SnapBack: mobile unreachable" / "SnapBack: mobile reconnected" | **Only on state transition**, never on steady state. Rate-limited to 1/min. |
| `snapback mobile status` | Peer name, last event time, queue depth, last error | On demand. |
| `snapback mobile logs` | Tail of `~/Library/Logs/SnapBack/bridge.log` | On demand. |

### 5.6 Config surface

Existing config API (`snapback-lib.sh`) adds two new scalar keys:

```bash
MOBILE_ENABLED="true"                    # master toggle; if false, bridge does not start
MOBILE_DEVICE_NAME="Samsung S24"         # informational, shown in status / menu-bar
```

Secrets (pair token) live in macOS Keychain, not in the config file.

New CLI subcommands:

- `snapback mobile pair` — launches SnapBackApp pairing UI.
- `snapback mobile unpair` — wipes token, notifies phone.
- `snapback mobile status` — prints peer, state, queue, last error.
- `snapback mobile logs` — tails bridge log.
- `snapback mobile enable | disable` — flips `MOBILE_ENABLED`.

### 5.7 Forward compatibility with N:M

Message format has a `v` field; every component validates it. Pair token is per-peer, so storing multiple tokens is a straightforward extension:

- Desktop Keychain: one token entry per paired phone.
- Phone Keystore: one token entry per paired desk.
- `hello` message carries sender identity, so receivers route by paired identity rather than assuming singleton.

MVP hard-codes one token each way and rejects a second pair attempt with a user-facing warning.

## 6. Error handling summary

| Situation | Behaviour |
|---|---|
| Bridge daemon down | Hook `nc` call silently fails, `&` swallows exit; sound + focus unaffected. |
| Phone unreachable | Event enqueued; retry 0.5 s / 2 s / 8 s, then dropped. Menu-bar transitions 🟢→🟡→🔴. User notified once on first transition. |
| HMAC mismatch | Message logged and dropped on both sides. After 5 consecutive mismatches, desktop auto-unpairs as a precaution (stale token). |
| Replay (seen nonce) | Dropped silently. |
| Clock skew | Tolerated within ±30 s; NTP normally keeps skew <1 s. |
| Desktop dies during HOLD | Phone misses heartbeats, exits HOLD after 60 s. |
| Phone dies during HOLD | Desktop retries/drops per policy; next `attention` re-establishes. |
| Device Admin revoked | Phone reports "degraded" in-app; bridge marked 🟡 with reason "phone permissions". |
| Accessibility revoked | Phone reports "gate disabled" — locks now apply unconditionally. |
| Duplicate pair attempt (MVP) | Desktop shows "already paired to X. Unpair first." |

## 7. Testing strategy

| Layer | Scope | Tooling |
|---|---|---|
| Bridge unit | HMAC, nonce cache, retry/backoff, codec round-trip | Swift XCTest |
| Bridge integration | Unix socket receive, in-process fake phone peer | Swift XCTest with loopback TCP |
| Android unit | Message parse, HMAC, HOLD state machine transitions, nonce cache | Kotlin JUnit |
| Android instrumented | Device Admin `lockNow`, Accessibility gate, re-lock loop | Espresso + emulator |
| End-to-end | Hook shell invocation → emulator lock screen observed | CI script: boot emulator, build bridge, trigger hook, assert `dumpsys power` state |
| Hook latency regression | `snapback.sh` under 10 ms on average with bridge absent | `tests/latency.bats` (new) |
| Existing bats | All current tests still pass unchanged | `bats tests/` |

## 8. Rollout plan

1. **Bridge-only MVP** (no phone app yet): daemon builds, listens on Unix socket, logs events, exposes menu-bar dot. Proves hook-latency design. Shippable alone.
2. **Protocol freeze**: finalize JSON schema, HMAC domain, mDNS service name. Write `docs/PROTOCOL.md`.
3. **Android MVP**: pair, attention, resume. No settings UI beyond enable/unpair.
4. **Fail-safes**: hard timeout, heartbeat, re-lock loop.
5. **Status surfaces**: menu-bar dot, macOS notifications, `snapback mobile status/logs`.
6. **Polish**: onboarding explainer screens for each Android permission; Settings history log; README.
7. **1.3.0 release**.

## 9. What this does not change

- `snapback.sh` remains the source of truth for desktop attention behaviour.
- Existing config keys, hooks, and CLI commands are untouched.
- Menu-bar app keeps its current surface; "Mobile" is a new tab, not a replacement.
- `get.sh` and `snapback update` keep working; mobile app ships separately (Play Store / sideload APK — to be decided in rollout step 3).
- No backend, no account, no telemetry.
