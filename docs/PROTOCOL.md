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
