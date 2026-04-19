# SnapBack Mobile (Android 1.4.0)

Android companion app for the SnapBack 1.3.0 desktop bridge. Force-locks your
phone when Claude Code blocks on you on the Mac.

## Build

Requirements: JDK 17, Android SDK with API 36.

```
cd SnapBackMobile
./gradlew :app:assembleDebug           # debug APK → app/build/outputs/apk/debug/
./gradlew :app:assembleRelease         # requires keystore/keystore.properties (see below)
./gradlew :app:testDebugUnitTest       # Robolectric + JUnit
./gradlew :app:connectedDebugAndroidTest  # Espresso (needs emulator or device)
```

## Sideload install (users)

1. Download `snapback-mobile-1.4.0-release.apk` from the GitHub Releases page.
2. Enable "Install from unknown sources" for your browser or file manager.
3. Open the APK file and accept the install.
4. On first launch, the app walks you through Accessibility permission + OEM battery-exemption setup.
5. Run `snapback mobile pair` on your Mac; scan the QR.

### Verifying the APK signature

The production keystore fingerprint (SHA-256) will be published here after the first release build.

## Release signing

The release keystore is not committed. Create `SnapBackMobile/keystore/keystore.properties`:

```
storeFile=keystore/release.jks
storePassword=<secret>
keyAlias=snapback-mobile
keyPassword=<secret>
```

Generate the keystore:

```
cd SnapBackMobile
keytool -genkeypair -v -keystore keystore/release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias snapback-mobile
```

`keystore/release.jks` and `keystore/keystore.properties` are gitignored.

## Emergency stop (debug builds only)

If the app hangs in HOLD on an emulator or test device, run:

```
adb shell am broadcast -a com.snapback.mobile.EMERGENCY_STOP \
  -n com.snapback.mobile.debug/com.snapback.mobile.service.EmergencyStopReceiver
```

This stops the foreground service and dismisses any overlay without any
network or state-machine involvement. The receiver is `exported=false`, so
other apps cannot reach it; `adb shell` targets it by explicit component.
Disabled entirely in release builds via `BuildConfig.EMERGENCY_STOP_ENABLED`.

## Manual smoke-test checklist

Full end-to-end verification requires a Mac running the 1.3.0 bridge + an
Android device (physical or emulator). See `SnapBackMobile/docs/smoke-test.md`.

## Deferred to manual testing (no emulator at build time)

The following are gated by hardware availability and must be run by a human
against a physical device or emulator before the 1.4.0 release goes public:

- `KeystoreTokenStoreInstrumentedTest` — real Android Keystore round-trip.
- Lock-driver smoke: install debug, enable Accessibility, tap "Test lock".
- End-to-end smoke: pair with a real Mac bridge, trigger `attention`, verify lock.

## Troubleshooting

- **App paired but the lock never fires**: ensure Accessibility is enabled (Settings → Accessibility → SnapBack Mobile → Enable). If you decline Accessibility, Device Admin works as a fallback (Settings → Security → Device Admin → SnapBack Mobile).
- **Bridge keeps disconnecting**: disable battery optimisation per your OEM (Settings → Battery → Unrestricted for SnapBack Mobile).
- **Samsung / Xiaomi / OnePlus drop the service after an hour**: follow the OEM card instructions in the app's Settings screen.

## Spec

See `docs/superpowers/specs/2026-04-18-mobile-companion-design.md` in the repo root.
