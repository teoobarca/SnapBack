# SnapBack Mobile — end-to-end smoke test

Prereqs:
- Mac with SnapBack 1.3.0 installed and SnapBack.app running.
- Android device (emulator or physical) with debug APK installed.
- Same WiFi network.

## Slice A: Pair + connect

1. On Mac: click SnapBack menu-bar → Mobile tab → "Pair mobile…".
2. Scan QR on Android.
3. On Mac: status dot should turn 🟢 within 5 s.
4. `snapback mobile status` should report "paired peer: <device>".

## Slice B: Test lock (with app open)

1. On Android SnapBack Mobile: tap "Test lock".
2. Expected: screen locks immediately via Accessibility.
3. Unlock. The app should still show "Bridge connected".

## Slice C: Full loop

1. Trigger a Claude Code hook on Mac: `./snapback.sh` from the repo root.
2. Expected: phone locks immediately (if screen was on & unlocked).
3. On Mac: type any prompt into Claude Code to dispatch `UserPromptSubmit`.
4. Expected: phone HOLD releases within ~200 ms (overlay dismisses if that was the active tier; lockscreen stays per normal Android semantics until next unlock).

## Fail-safes

1. Trigger `attention` but don't resume. Wait 2 minutes (debug build). HOLD auto-expires.
2. Trigger `attention`, then kill Mac bridge via `pkill -f SnapBack`. Within 60–120 s the phone side should exit HOLD on heartbeat timeout.
3. Trigger `attention`, then from the app tap "Release hold". HOLD exits immediately.
4. DEBUG ONLY: Trigger `attention`, then `adb shell am broadcast -a com.snapback.mobile.EMERGENCY_STOP`. Service stops immediately.

## Known limitations

- Samsung One UI may kill the foreground service after ~60 min of no interaction unless battery optimisation is unrestricted — follow the OEM card guidance.
- Xiaomi MIUI suppresses `NsdManager` advertising when the screen is off beyond ~5 min; holding `MulticastLock` mitigates this but reconnection can take up to 30 s when screen comes back on.
- mDNS discovery fails across VLANs or WiFi-guest-isolation networks. Phone and Mac must be on the same LAN segment.
