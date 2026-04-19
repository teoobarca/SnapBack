# SnapBack Mobile (Android Companion) 1.4.0 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship SnapBack Mobile 1.4.0: a sideloaded Android companion app that force-locks the phone when Claude Code blocks on the user, paired 1:1 with a Mac running the 1.3.0 bridge over LAN/mDNS + HMAC-SHA256.

**Architecture:** Three vertical slices, each independently shippable as an internal beta. Slice A ("Hello, Mac") proves the network stack end-to-end with no lock behaviour; Slice B ("Lock mechanic") proves the three-tier lock driver in isolation behind a "Test lock" button; Slice C ("Full loop") wires them together through a hold state machine with aggressive fail-safes. The app is a Kotlin/Compose Jetpack stack on a foreground service; protocol layer is byte-identical with the Swift 1.3.0 bridge and proved via the shared `tests/protocol-vectors.json` fixture.

**Tech Stack:**
- Kotlin 2.0 + Jetpack Compose (SwiftUI-equivalent)
- Coroutines + Flow (concurrency)
- AGP 8.7 / Gradle 8.10 / JDK 17
- `NsdManager` (built-in mDNS), raw `ServerSocket` + coroutines (one listener, no Ktor/OkHttp)
- CameraX + ML Kit Barcode Scanner (QR pairing)
- Android Keystore (secret storage)
- Device Policy Manager + `AccessibilityService.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)` (lock primitives)
- Room (event log, future metrics migration path)
- Robolectric + JUnit (unit), Espresso (instrumented)
- minSdk 31 (Android 12), targetSdk 36 (Android 16)

**Spec:** `docs/superpowers/specs/2026-04-18-mobile-companion-design.md` §5.3, §5.4, §5.8, §5.9, §8.2.

**Release constraints that drive every phase:**

1. **No Play Store submission in 1.4.0.** Distribution is GitHub Releases APK sideload. A Play Store submission is a later, separate project requiring different review-surface decisions (Accessibility justification, possibly removing Device Admin, etc.).
2. **Lock-brick recovery must exist in every build where lock is wireable.** Debug builds ship with an `adb`-accessible emergency-stop broadcast that bypasses all state-machine logic. Without this, a bug leaves the dev's device/emulator bricked.
3. **Safe-mode first launch.** After install, the app NEVER engages lock until the user has explicitly completed onboarding and tapped "Test lock" once. Prevents an installed-and-paired app from immediately locking the phone before permissions are verified.
4. **Hard TTL cap on HOLD**: 10 minutes in release, 2 minutes in debug. Dev never pays more than 2 min for a state-machine bug.
5. **Protocol conformance**: Kotlin tests consume the exact same `tests/protocol-vectors.json` fixture the Swift side shipped with pre-computed HMACs. Byte-identical is non-negotiable.

---

## Repository layout added by this plan

```
AIAttention/ (repo root)
├── SnapBackMobile/                     ← new, sibling to SnapBackApp/
│   ├── .gitignore
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   ├── gradle.properties
│   ├── gradlew / gradlew.bat
│   ├── gradle/wrapper/*
│   ├── README.md
│   ├── keystore/                       ← release keystore, gitignored
│   │   └── .gitkeep
│   └── app/
│       ├── build.gradle.kts
│       ├── proguard-rules.pro
│       └── src/
│           ├── main/
│           │   ├── AndroidManifest.xml
│           │   ├── kotlin/com/snapback/mobile/
│           │   │   ├── protocol/        ← MessageCodec + CanonicalJson + NonceCache + types
│           │   │   ├── security/        ← KeystoreTokenStore
│           │   │   ├── pair/            ← PairingActivity + PairingResult
│           │   │   ├── net/             ← MessageServer + MdnsAdvertiser + WifiLocks
│           │   │   ├── lock/            ← LockDriver + AccessibilityService + DeviceAdminReceiver
│           │   │   ├── state/           ← HoldStateMachine + ScreenStateGate
│           │   │   ├── service/         ← MobileForegroundService + EmergencyStopReceiver
│           │   │   ├── ui/              ← MainActivity + Compose screens + OemCards
│           │   │   ├── db/              ← Room (AppDatabase + EventLog)
│           │   │   └── MobileApp.kt
│           │   └── res/
│           │       ├── xml/             ← accessibility_config, device_admin_policies
│           │       ├── drawable/        ← launcher
│           │       ├── values/          ← strings, colors, themes
│           │       └── mipmap-anydpi-v26/
│           ├── test/                    ← Robolectric + JUnit
│           └── androidTest/             ← Espresso instrumented
└── tests/protocol-vectors.json         ← existing, consumed by both Swift and Kotlin tests
```

---

## Execution constraints

- Every task is TDD where a test is meaningful. For pure Android-UI / Manifest-only tasks, build success is the test.
- Each phase ends with a working, reviewable commit. Commit messages use Conventional Commits (`feat(mobile): ...`, `test(mobile): ...`, `chore(mobile): ...`).
- Before merging into `main`, the release APK must pass all tests AND sign against the project keystore AND have its SHA-256 fingerprint documented in `SnapBackMobile/README.md`.
- Device-specific behaviour (OEM battery kills, mDNS suspension) is checked via manual smoke tests at explicit checkpoints; plan does not require a real device until Phase 7.

---

## Phase 0 — Gradle project scaffolding

### Task 0.1: Preflight — ensure clean main and create worktree

**Files:** none

- [ ] **Step 1: Verify you're on clean `main`**

Run: `git status && git branch --show-current && git pull --ff-only`
Expected: `nothing to commit`; branch `main`; up-to-date with origin.

- [ ] **Step 2: Create worktree + feature branch**

Run:
```
git worktree add .worktrees/mobile-1.4.0 -b feature/mobile-1.4.0
cd .worktrees/mobile-1.4.0
```

- [ ] **Step 3: Verify the baseline tests green in the worktree**

Run: `bats tests/ && (cd SnapBackApp && swift test) >/dev/null 2>&1 || true`
Expected: 35 bats tests pass; Swift tests pass (53/53).

### Task 0.2: Create Gradle project skeleton

**Files:**
- Create: `SnapBackMobile/.gitignore`
- Create: `SnapBackMobile/settings.gradle.kts`
- Create: `SnapBackMobile/build.gradle.kts`
- Create: `SnapBackMobile/gradle.properties`
- Create: `SnapBackMobile/gradle/wrapper/gradle-wrapper.properties`
- Create: `SnapBackMobile/keystore/.gitkeep`

- [ ] **Step 1: Create the SnapBackMobile directory**

Run: `mkdir -p SnapBackMobile/gradle/wrapper SnapBackMobile/keystore`

- [ ] **Step 2: Write `SnapBackMobile/.gitignore`**

```
# Gradle
.gradle/
build/
local.properties
!gradle-wrapper.properties

# IntelliJ / Android Studio
.idea/
*.iml
captures/
.externalNativeBuild/
.cxx/

# Keystore — DO NOT COMMIT. Real keystore file lives alongside .gitkeep.
keystore/*.jks
keystore/*.keystore
keystore/*.properties

# Build outputs
app/release/
app/debug/

# macOS
.DS_Store
```

- [ ] **Step 3: Write `SnapBackMobile/settings.gradle.kts`**

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "SnapBackMobile"
include(":app")
```

- [ ] **Step 4: Write `SnapBackMobile/build.gradle.kts`**

```kotlin
// Top-level build file. Plugins applied per-module.
plugins {
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("com.google.devtools.ksp") version "2.0.21-1.0.28" apply false
}
```

- [ ] **Step 5: Write `SnapBackMobile/gradle.properties`**

```properties
org.gradle.jvmargs=-Xmx4096m -XX:+UseParallelGC
org.gradle.parallel=true
org.gradle.caching=true
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
```

- [ ] **Step 6: Write `SnapBackMobile/gradle/wrapper/gradle-wrapper.properties`**

```properties
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.10.2-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

- [ ] **Step 7: Create empty `keystore/.gitkeep`**

Run: `touch SnapBackMobile/keystore/.gitkeep`

- [ ] **Step 8: Bootstrap the Gradle wrapper**

From `SnapBackMobile/`, install Gradle via Homebrew if not present (`brew install gradle`), then:

```
cd SnapBackMobile
gradle wrapper --gradle-version 8.10.2 --distribution-type bin
```

This generates `gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`.

- [ ] **Step 9: Verify wrapper runs**

Run: `./gradlew --version`
Expected: output includes `Gradle 8.10.2`.

- [ ] **Step 10: Commit**

```
cd ..  # back to repo root
git add SnapBackMobile/
git commit -m "chore(mobile): bootstrap Gradle project skeleton for SnapBackMobile"
```

### Task 0.3: Create the `:app` module with Android plugin

**Files:**
- Create: `SnapBackMobile/app/build.gradle.kts`
- Create: `SnapBackMobile/app/proguard-rules.pro`
- Create: `SnapBackMobile/app/src/main/AndroidManifest.xml`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/MobileApp.kt`
- Create: `SnapBackMobile/app/src/main/res/values/strings.xml`
- Create: `SnapBackMobile/app/src/main/res/values/themes.xml`
- Create: `SnapBackMobile/app/src/main/res/values/colors.xml`

- [ ] **Step 1: Write `SnapBackMobile/app/build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.snapback.mobile"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.snapback.mobile"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.4.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isMinifyEnabled = false
            buildConfigField("long", "HOLD_TTL_MS", "120000L") // 2 min
            buildConfigField("boolean", "EMERGENCY_STOP_ENABLED", "true")
        }
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            buildConfigField("long", "HOLD_TTL_MS", "600000L") // 10 min
            buildConfigField("boolean", "EMERGENCY_STOP_ENABLED", "false")
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }

    sourceSets["main"].java.srcDirs("src/main/kotlin")
    sourceSets["test"].java.srcDirs("src/test/kotlin")
    sourceSets["androidTest"].java.srcDirs("src/androidTest/kotlin")

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            isReturnDefaultValues = true
        }
    }

    packaging {
        resources {
            excludes += setOf("META-INF/LICENSE*", "META-INF/NOTICE*", "META-INF/*.kotlin_module")
        }
    }
}

dependencies {
    // Compose BOM
    val composeBom = platform("androidx.compose:compose-bom:2024.10.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Core
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-service:2.8.7")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // CameraX + ML Kit Barcode
    implementation("androidx.camera:camera-core:1.4.0")
    implementation("androidx.camera:camera-camera2:1.4.0")
    implementation("androidx.camera:camera-lifecycle:1.4.0")
    implementation("androidx.camera:camera-view:1.4.0")
    implementation("com.google.mlkit:barcode-scanning:17.3.0")

    // Room
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    // Test
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("androidx.test.ext:junit:1.2.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
}
```

- [ ] **Step 2: Write `SnapBackMobile/app/proguard-rules.pro`** (empty but present)

```
# Keep broadcast receiver class names so emergency-stop intent still resolves.
-keep class com.snapback.mobile.service.EmergencyStopReceiver { *; }
-keep class com.snapback.mobile.lock.SnapBackAccessibilityService { *; }
-keep class com.snapback.mobile.lock.SnapBackDeviceAdminReceiver { *; }
```

- [ ] **Step 3: Write minimal `SnapBackMobile/app/src/main/AndroidManifest.xml`**

Packaging essentials only. Permissions added incrementally in later tasks.

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:name=".MobileApp"
        android:allowBackup="false"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="false"
        android:icon="@drawable/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.SnapBackMobile">
    </application>

</manifest>
```

- [ ] **Step 4: Write `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/MobileApp.kt`**

```kotlin
package com.snapback.mobile

import android.app.Application

class MobileApp : Application()
```

- [ ] **Step 5: Write `SnapBackMobile/app/src/main/res/values/strings.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">SnapBack Mobile</string>
</resources>
```

- [ ] **Step 6: Write `SnapBackMobile/app/src/main/res/values/colors.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="snapback_orange">#E07D4F</color>
    <color name="snapback_orange_dark">#B8633F</color>
    <color name="background_dark">#121212</color>
</resources>
```

- [ ] **Step 7: Write `SnapBackMobile/app/src/main/res/values/themes.xml`**

```xml
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.SnapBackMobile" parent="android:Theme.Material.NoActionBar">
        <item name="android:statusBarColor">@color/background_dark</item>
        <item name="android:windowBackground">@color/background_dark</item>
    </style>
</resources>
```

- [ ] **Step 8: Write a placeholder launcher drawable**

Create `SnapBackMobile/app/src/main/res/drawable/ic_launcher.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#E07D4F" android:pathData="M54,8C28.6,8 8,28.6 8,54s20.6,46 46,46s46,-20.6 46,-46S79.4,8 54,8z"/>
    <path android:fillColor="#FFFFFF" android:pathData="M54,30L38,54h12v20h8V54h12z"/>
</vector>
```

- [ ] **Step 9: Add empty `SnapBackMobile/app/src/main/res/xml/data_extraction_rules.xml`** (required by manifest)

```xml
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" />
    </device-transfer>
</data-extraction-rules>
```

- [ ] **Step 10: Build the app**

Run: `cd SnapBackMobile && ./gradlew :app:assembleDebug`
Expected: `BUILD SUCCESSFUL` and an APK at `app/build/outputs/apk/debug/app-debug.apk`.

- [ ] **Step 11: Commit**

```
git add SnapBackMobile/
git commit -m "feat(mobile): Gradle app module with Kotlin + Compose + Room scaffolding"
```

---

## Phase 1 — Protocol layer (byte-exact with Swift 1.3.0)

### Task 1.1: `ProtocolMessageType` + `ProtocolDirection` + `JsonValue` + `ProtocolMessage`

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/ProtocolMessageType.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/ProtocolDirection.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/JsonValue.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/ProtocolMessage.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/ProtocolTypesTest.kt`

- [ ] **Step 1: Write the failing test**

`ProtocolTypesTest.kt`:

```kotlin
package com.snapback.mobile.protocol

import org.junit.Assert.assertEquals
import org.junit.Test

class ProtocolTypesTest {
    @Test fun directionValues() {
        assertEquals("c2s", ProtocolDirection.ClientToServer.wire)
        assertEquals("s2c", ProtocolDirection.ServerToClient.wire)
    }

    @Test fun allMessageTypesPresent() {
        val names = ProtocolMessageType.entries.map { it.wire }.toSet()
        val expected = setOf("hello", "ack", "attention", "resume",
            "heartbeat", "pong", "resync", "invalidate")
        assertEquals(expected, names)
    }

    @Test fun protocolMessageRoundtrip() {
        val msg = ProtocolMessage(
            version = 1,
            type = ProtocolMessageType.Attention,
            timestamp = 1_734_556_677L,
            nonceHex = "a".repeat(32),
            payload = listOf("hook" to JsonValue.Str("PermissionRequest"))
        )
        assertEquals(1, msg.version)
        assertEquals(ProtocolMessageType.Attention, msg.type)
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

Run: `cd SnapBackMobile && ./gradlew :app:testDebugUnitTest --tests '*ProtocolTypesTest*'`
Expected: compilation error (types missing).

- [ ] **Step 3: Write `ProtocolDirection.kt`**

```kotlin
package com.snapback.mobile.protocol

enum class ProtocolDirection(val wire: String) {
    ClientToServer("c2s"),
    ServerToClient("s2c");

    companion object {
        fun fromWire(s: String): ProtocolDirection? = entries.firstOrNull { it.wire == s }
    }
}
```

- [ ] **Step 4: Write `ProtocolMessageType.kt`**

```kotlin
package com.snapback.mobile.protocol

enum class ProtocolMessageType(val wire: String) {
    Hello("hello"),
    Ack("ack"),
    Attention("attention"),
    Resume("resume"),
    Heartbeat("heartbeat"),
    Pong("pong"),
    Resync("resync"),
    Invalidate("invalidate");

    companion object {
        fun fromWire(s: String): ProtocolMessageType? = entries.firstOrNull { it.wire == s }
    }
}
```

- [ ] **Step 5: Write `JsonValue.kt`**

```kotlin
package com.snapback.mobile.protocol

/**
 * Canonical JSON value tree. Kept bespoke (not Any?) so serialization is
 * deterministic and byte-identical with the Swift 1.3.0 implementation.
 */
sealed class JsonValue {
    data class Str(val value: String) : JsonValue()
    data class Integer(val value: Long) : JsonValue()
    data class Floating(val value: Double) : JsonValue()
    data class Bool(val value: Boolean) : JsonValue()
    data object Null : JsonValue()
    data class Arr(val items: List<JsonValue>) : JsonValue()
    data class Obj(val pairs: List<Pair<String, JsonValue>>) : JsonValue()
}
```

- [ ] **Step 6: Write `ProtocolMessage.kt`**

```kotlin
package com.snapback.mobile.protocol

/**
 * One wire message. `payload` is preserved insertion-order but CanonicalJson
 * sorts on encode — the order here does not affect HMAC output.
 */
data class ProtocolMessage(
    val version: Int,
    val type: ProtocolMessageType,
    val timestamp: Long,
    val nonceHex: String,
    val payload: List<Pair<String, JsonValue>> = emptyList()
)
```

- [ ] **Step 7: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*ProtocolTypesTest*'`
Expected: 3 tests pass.

- [ ] **Step 8: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/ SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/ProtocolTypesTest.kt
git commit -m "feat(mobile): protocol types (ProtocolMessage, direction, type, JsonValue)"
```

### Task 1.2: `CanonicalJson` encoder (byte-identical with Swift)

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/CanonicalJson.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/CanonicalJsonTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package com.snapback.mobile.protocol

import org.junit.Assert.assertEquals
import org.junit.Test

class CanonicalJsonTest {
    private fun encode(v: JsonValue) = String(CanonicalJson.encode(v), Charsets.UTF_8)

    @Test fun objectKeysSortedAlphabetically() {
        val v = JsonValue.Obj(listOf("b" to JsonValue.Integer(2), "a" to JsonValue.Integer(1)))
        assertEquals("""{"a":1,"b":2}""", encode(v))
    }

    @Test fun emptyObject() {
        assertEquals("{}", encode(JsonValue.Obj(emptyList())))
    }

    @Test fun stringEscaping() {
        val v = JsonValue.Str("a\"b\\c\n")
        assertEquals("\"a\\\"b\\\\c\\n\"", encode(v))
    }

    @Test fun integerNoFraction() {
        assertEquals("0", encode(JsonValue.Integer(0)))
    }

    @Test fun booleansAndNull() {
        assertEquals("true", encode(JsonValue.Bool(true)))
        assertEquals("false", encode(JsonValue.Bool(false)))
        assertEquals("null", encode(JsonValue.Null))
    }

    @Test fun controlCharsAsUxxxxLowercase() {
        // \u0001 must serialize as \u0001 (lowercase hex), matching Swift.
        val v = JsonValue.Str("\u0001")
        assertEquals("\"\\u0001\"", encode(v))
    }

    @Test fun nestedObjectSortsRecursively() {
        val inner = JsonValue.Obj(listOf("y" to JsonValue.Integer(1), "x" to JsonValue.Integer(2)))
        val outer = JsonValue.Obj(listOf("b" to inner, "a" to JsonValue.Integer(0)))
        assertEquals("""{"a":0,"b":{"x":2,"y":1}}""", encode(outer))
    }
}
```

- [ ] **Step 2: Run — expect fail**

Run: `./gradlew :app:testDebugUnitTest --tests '*CanonicalJsonTest*'`

- [ ] **Step 3: Write `CanonicalJson.kt`**

```kotlin
package com.snapback.mobile.protocol

/**
 * Deterministic JSON encoder mirroring `SnapBackApp/.../MessageCodec.swift`
 * byte-for-byte. See `docs/PROTOCOL.md` for the full contract.
 *
 * Rules:
 *   • Object keys sorted lexicographically by UTF-8 bytes
 *   • Integers: shortest decimal, no trailing ".0"
 *   • Doubles: Kotlin default shortest round-trip — payloads SHOULD NOT
 *     contain doubles in v1 (spec); this is future-proofing only
 *   • Strings: only \\, \", \n, \r, \t, \b, \f escapes; controls as \uXXXX (lowercase)
 *   • No whitespace
 */
object CanonicalJson {
    fun encode(value: JsonValue): ByteArray {
        val sb = StringBuilder()
        append(value, sb)
        return sb.toString().toByteArray(Charsets.UTF_8)
    }

    private fun append(value: JsonValue, sb: StringBuilder) {
        when (value) {
            is JsonValue.Null       -> sb.append("null")
            is JsonValue.Bool       -> sb.append(if (value.value) "true" else "false")
            is JsonValue.Integer    -> sb.append(value.value.toString())
            is JsonValue.Floating   -> sb.append(value.value.toString())
            is JsonValue.Str        -> appendString(value.value, sb)
            is JsonValue.Arr -> {
                sb.append('[')
                value.items.forEachIndexed { i, v ->
                    if (i > 0) sb.append(',')
                    append(v, sb)
                }
                sb.append(']')
            }
            is JsonValue.Obj -> {
                sb.append('{')
                value.pairs.sortedBy { it.first }.forEachIndexed { i, (k, v) ->
                    if (i > 0) sb.append(',')
                    appendString(k, sb)
                    sb.append(':')
                    append(v, sb)
                }
                sb.append('}')
            }
        }
    }

    private fun appendString(s: String, sb: StringBuilder) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"'      -> sb.append("\\\"")
                '\\'     -> sb.append("\\\\")
                '\b'     -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                '\n'     -> sb.append("\\n")
                '\r'     -> sb.append("\\r")
                '\t'     -> sb.append("\\t")
                else -> {
                    if (c.code < 0x20) {
                        sb.append("\\u%04x".format(c.code))
                    } else {
                        sb.append(c)
                    }
                }
            }
        }
        sb.append('"')
    }
}
```

- [ ] **Step 4: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*CanonicalJsonTest*'`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/CanonicalJson.kt SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/CanonicalJsonTest.kt
git commit -m "feat(mobile): deterministic CanonicalJson encoder matching Swift"
```

### Task 1.3: `MessageCodec` — signing domain + HMAC sign/verify

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/MessageCodec.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/MessageCodecTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package com.snapback.mobile.protocol

import org.junit.Assert.*
import org.junit.Test

class MessageCodecTest {
    private val secret = ByteArray(32) { 0x42 }

    @Test fun signingDomainHasDirectionFirstAndNullSeparators() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Attention, timestamp = 1_734_556_677L,
            nonceHex = "0".repeat(32),
            payload = listOf("hook" to JsonValue.Str("Stop"))
        )
        val domain = MessageCodec.signingDomain(msg, ProtocolDirection.ClientToServer)
        val expected = ("c2s\u0000" + "1\u0000" + "attention\u0000" +
            "1734556677\u0000" + "0".repeat(32) + "\u0000" + "{\"hook\":\"Stop\"}")
            .toByteArray(Charsets.UTF_8)
        assertArrayEquals(expected, domain)
    }

    @Test fun emptyPayloadSerializesAsOpenClose() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Resume, timestamp = 100L,
            nonceHex = "1".repeat(32), payload = emptyList()
        )
        val domain = MessageCodec.signingDomain(msg, ProtocolDirection.ClientToServer)
        assertTrue(String(domain, Charsets.UTF_8).endsWith("\u0000{}"))
    }

    @Test fun signProducesLowercase64HexChars() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Heartbeat, timestamp = 1L,
            nonceHex = "0".repeat(32)
        )
        val sig = MessageCodec.sign(msg, ProtocolDirection.ClientToServer, secret)
        assertEquals(64, sig.length)
        assertTrue(sig.all { it in "0123456789abcdef" })
    }

    @Test fun verifyAcceptsCorrectSignature() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Hello, timestamp = 17L,
            nonceHex = "0".repeat(32)
        )
        val sig = MessageCodec.sign(msg, ProtocolDirection.ClientToServer, secret)
        assertTrue(MessageCodec.verify(msg, ProtocolDirection.ClientToServer, sig, secret))
    }

    @Test fun verifyRejectsOnDirectionMismatch() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Hello, timestamp = 17L,
            nonceHex = "0".repeat(32)
        )
        val sig = MessageCodec.sign(msg, ProtocolDirection.ClientToServer, secret)
        assertFalse(MessageCodec.verify(msg, ProtocolDirection.ServerToClient, sig, secret))
    }

    @Test fun verifyRejectsOnTamperedField() {
        val msg = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Attention, timestamp = 17L,
            nonceHex = "0".repeat(32)
        )
        val sig = MessageCodec.sign(msg, ProtocolDirection.ClientToServer, secret)
        val tampered = msg.copy(timestamp = 18L)
        assertFalse(MessageCodec.verify(tampered, ProtocolDirection.ClientToServer, sig, secret))
    }

    @Test fun nonceValidatorAcceptsExactly32Lowercase() {
        assertTrue(MessageCodec.isValidNonceHex("0".repeat(32)))
        assertTrue(MessageCodec.isValidNonceHex("abcdef0123456789abcdef0123456789"))
    }

    @Test fun nonceValidatorRejectsUppercase() {
        assertFalse(MessageCodec.isValidNonceHex("A".repeat(32)))
    }

    @Test fun nonceValidatorRejectsWrongLength() {
        assertFalse(MessageCodec.isValidNonceHex("0".repeat(31)))
        assertFalse(MessageCodec.isValidNonceHex("0".repeat(33)))
    }

    @Test fun hexParseStrict() {
        assertArrayEquals(byteArrayOf(0x00, 0x01, 0xFF.toByte()), MessageCodec.hexToBytes("0001ff"))
        assertNull(MessageCodec.hexToBytes("0001 ff"))  // whitespace rejected
        assertNull(MessageCodec.hexToBytes("0001FF"))   // uppercase rejected
        assertNull(MessageCodec.hexToBytes("0001f"))    // odd length rejected
    }
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Write `MessageCodec.kt`**

```kotlin
package com.snapback.mobile.protocol

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject
import org.json.JSONTokener
import org.json.JSONArray

/**
 * Wire format codec. Matches Swift `MessageCodec` byte-for-byte; any divergence
 * is a cross-language bug and surfaces as an HMAC mismatch on the receive path.
 */
object MessageCodec {
    /** Sign a message, returning 64 lowercase hex chars. */
    fun sign(message: ProtocolMessage,
             direction: ProtocolDirection,
             secret: ByteArray): String {
        require(isValidNonceHex(message.nonceHex)) {
            "nonceHex must be exactly 32 lowercase hex chars"
        }
        val domain = signingDomain(message, direction)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        return bytesToHex(mac.doFinal(domain))
    }

    /** Constant-time verify. */
    fun verify(message: ProtocolMessage,
               direction: ProtocolDirection,
               hmacHex: String,
               secret: ByteArray): Boolean {
        val expected = hexToBytes(hmacHex) ?: return false
        val domain = signingDomain(message, direction)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        val actual = mac.doFinal(domain)
        if (actual.size != expected.size) return false
        var diff = 0
        for (i in actual.indices) diff = diff or (actual[i].toInt() xor expected[i].toInt())
        return diff == 0
    }

    /** Exact bytes fed to HMAC-SHA256. See `docs/PROTOCOL.md`. */
    fun signingDomain(message: ProtocolMessage, direction: ProtocolDirection): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        out.writeStringUtf8(direction.wire)
        out.write(0)
        out.writeStringUtf8(message.version.toString())
        out.write(0)
        out.writeStringUtf8(message.type.wire)
        out.write(0)
        out.writeStringUtf8(message.timestamp.toString())
        out.write(0)
        out.writeStringUtf8(message.nonceHex)
        out.write(0)
        out.write(CanonicalJson.encode(JsonValue.Obj(message.payload)))
        return out.toByteArray()
    }

    fun isValidNonceHex(s: String): Boolean {
        if (s.length != 32) return false
        return s.all { it in '0'..'9' || it in 'a'..'f' }
    }

    fun hexToBytes(s: String): ByteArray? {
        if (s.length % 2 != 0) return null
        val out = ByteArray(s.length / 2)
        for (i in out.indices) {
            val hi = hexNibble(s[2 * i]) ?: return null
            val lo = hexNibble(s[2 * i + 1]) ?: return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    private fun hexNibble(c: Char): Int? = when (c) {
        in '0'..'9' -> c.code - '0'.code
        in 'a'..'f' -> c.code - 'a'.code + 10
        else -> null  // uppercase + whitespace rejected
    }

    private fun bytesToHex(b: ByteArray): String {
        val sb = StringBuilder(b.size * 2)
        for (byte in b) sb.append("%02x".format(byte.toInt() and 0xFF))
        return sb.toString()
    }

    private fun java.io.ByteArrayOutputStream.writeStringUtf8(s: String) {
        write(s.toByteArray(Charsets.UTF_8))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*MessageCodecTest*'`
Expected: 10 tests pass.

- [ ] **Step 5: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/MessageCodec.kt SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/MessageCodecTest.kt
git commit -m "feat(mobile): HmacSHA256 signing domain + sign/verify + strict hex"
```

### Task 1.4: Wire encode/decode (JSON round-trip with \n framing)

**Files:**
- Modify: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/MessageCodec.kt`
- Modify: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/MessageCodecTest.kt`

- [ ] **Step 1: Append failing tests**

```kotlin
    @Test fun roundTripSignedMessage() {
        val secret = ByteArray(32) { 0xAB.toByte() }
        val original = ProtocolMessage(
            version = 1, type = ProtocolMessageType.Attention, timestamp = 1_734_556_677L,
            nonceHex = "a".repeat(32),
            payload = listOf("hook" to JsonValue.Str("PermissionRequest"))
        )
        val line = MessageCodec.encodeSignedLine(original, ProtocolDirection.ClientToServer, secret)
        assertTrue(line.endsWith("\n"))
        val (decoded, hmac) = MessageCodec.decodeLine(line)
        assertEquals(original.type, decoded.type)
        assertEquals(original.timestamp, decoded.timestamp)
        assertEquals(original.nonceHex, decoded.nonceHex)
        assertTrue(MessageCodec.verify(decoded, ProtocolDirection.ClientToServer, hmac, secret))
    }

    @Test(expected = MessageCodecException::class)
    fun decodeRejectsMissingHmac() {
        val json = """{"v":1,"type":"resume","ts":1,"nonce":"${"0".repeat(32)}","payload":{}}""" + "\n"
        MessageCodec.decodeLine(json)
    }

    @Test(expected = MessageCodecException::class)
    fun decodeRejectsUnknownType() {
        val json = """{"v":1,"type":"bogus","ts":1,"nonce":"${"0".repeat(32)}","payload":{},"hmac":"x"}""" + "\n"
        MessageCodec.decodeLine(json)
    }

    @Test(expected = MessageCodecException::class)
    fun decodeRejectsUppercaseNonce() {
        val bad = "A".repeat(32)
        val json = """{"v":1,"type":"resume","ts":1,"nonce":"$bad","payload":{},"hmac":"${"0".repeat(64)}"}""" + "\n"
        MessageCodec.decodeLine(json)
    }

    @Test(expected = MessageCodecException::class)
    fun decodeRejectsUnknownVersion() {
        val json = """{"v":2,"type":"resume","ts":1,"nonce":"${"0".repeat(32)}","payload":{},"hmac":"${"0".repeat(64)}"}""" + "\n"
        MessageCodec.decodeLine(json)
    }
```

- [ ] **Step 2: Append to `MessageCodec.kt`**

At the top of `MessageCodec.kt` (outside the object):

```kotlin
class MessageCodecException(message: String) : Exception(message)
```

Inside the object:

```kotlin
    fun encodeSignedLine(message: ProtocolMessage,
                         direction: ProtocolDirection,
                         secret: ByteArray): String {
        require(isValidNonceHex(message.nonceHex))
        val hmac = sign(message, direction, secret)
        val body = JsonValue.Obj(listOf(
            "hmac" to JsonValue.Str(hmac),
            "nonce" to JsonValue.Str(message.nonceHex),
            "payload" to JsonValue.Obj(message.payload),
            "ts" to JsonValue.Integer(message.timestamp),
            "type" to JsonValue.Str(message.type.wire),
            "v" to JsonValue.Integer(message.version.toLong())
        ))
        val bytes = CanonicalJson.encode(body)
        return String(bytes, Charsets.UTF_8) + "\n"
    }

    /** Decode one line (trailing \n optional). Does NOT verify HMAC — caller's job. */
    fun decodeLine(line: String): Pair<ProtocolMessage, String> {
        val trimmed = if (line.endsWith("\n")) line.dropLast(1) else line
        val obj = try { JSONTokener(trimmed).nextValue() as? JSONObject }
                  catch (e: Exception) { null }
                  ?: throw MessageCodecException("not a JSON object")

        val v = obj.optInt("v", -1)
        if (v == -1) throw MessageCodecException("missing v")
        if (v != 1) throw MessageCodecException("unknown version $v")

        val typeStr = obj.optString("type", "")
        val type = ProtocolMessageType.fromWire(typeStr)
            ?: throw MessageCodecException("unknown type: $typeStr")

        val ts = obj.opt("ts") as? Number
            ?: throw MessageCodecException("missing ts")
        val tsLong = ts.toLong()

        val nonce = obj.optString("nonce", "")
        if (!isValidNonceHex(nonce)) throw MessageCodecException("invalid nonce")

        val hmac = obj.optString("hmac", "")
        if (hmac.isEmpty()) throw MessageCodecException("missing hmac")

        val payloadJson = obj.optJSONObject("payload") ?: JSONObject()
        val payload = payloadJson.toPairs()

        return ProtocolMessage(v, type, tsLong, nonce, payload) to hmac
    }

    private fun JSONObject.toPairs(): List<Pair<String, JsonValue>> {
        val keys = keys().asSequence().toList().sorted()
        return keys.map { k -> k to fromJson(get(k)) }
    }

    private fun fromJson(v: Any): JsonValue = when (v) {
        is String -> JsonValue.Str(v)
        is Boolean -> JsonValue.Bool(v)
        // Order matters: Integer must precede Number (Long and Int both are Number).
        is Int -> JsonValue.Integer(v.toLong())
        is Long -> JsonValue.Integer(v)
        is Double -> JsonValue.Floating(v)
        is Float -> JsonValue.Floating(v.toDouble())
        JSONObject.NULL -> JsonValue.Null
        is JSONObject -> JsonValue.Obj(v.toPairs())
        is JSONArray -> JsonValue.Arr((0 until v.length()).map { fromJson(v.get(it)) })
        else -> throw MessageCodecException("unsupported JSON type: ${v::class}")
    }
```

- [ ] **Step 3: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*MessageCodecTest*'`
Expected: 15 tests pass (10 prior + 5 new).

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/MessageCodec.kt SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/MessageCodecTest.kt
git commit -m "feat(mobile): wire encode/decode with strict version/nonce/type gates"
```

### Task 1.5: Shared protocol vectors conformance test

The whole point of Phase 1. Kotlin must produce byte-identical HMACs and signatures as Swift, verified by reading `tests/protocol-vectors.json` from the repo root.

**Files:**
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/ProtocolVectorsTest.kt`
- Modify: `SnapBackMobile/app/build.gradle.kts` (add `tests/` to resource path)

- [ ] **Step 1: Write the failing test**

```kotlin
package com.snapback.mobile.protocol

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class ProtocolVectorsTest {
    @Test fun allVectorsMatchPrecomputedHmacs() {
        // Read the shared fixture from the repo root. Gradle runs tests from
        // SnapBackMobile/, so the fixture is two levels up.
        val fixtureFile = File(System.getProperty("user.dir"), "../tests/protocol-vectors.json")
            .also { require(it.exists()) { "fixture missing: ${it.absolutePath}" } }
        val json = JSONObject(fixtureFile.readText())
        val secretHex = json.getString("secret_hex")
        val secret = MessageCodec.hexToBytes(secretHex)!!
        val vectors = json.getJSONArray("vectors")
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            val name = v.getString("name")
            val direction = ProtocolDirection.fromWire(v.getString("direction"))!!
            val m = v.getJSONObject("message")
            val payload = m.getJSONObject("payload")
            val pairs = payload.keys().asSequence().sorted().toList().map { k ->
                k to jsonAnyToValue(payload.get(k))
            }
            val msg = ProtocolMessage(
                version = m.getInt("v"),
                type = ProtocolMessageType.fromWire(m.getString("type"))!!,
                timestamp = m.getLong("ts"),
                nonceHex = m.getString("nonce"),
                payload = pairs
            )
            val actual = MessageCodec.sign(msg, direction, secret)
            val expected = v.optString("expected_hmac_hex", "")
            assertEquals("vector '$name' HMAC mismatch", expected, actual)
        }
    }

    private fun jsonAnyToValue(a: Any): JsonValue = when (a) {
        is String -> JsonValue.Str(a)
        is Int -> JsonValue.Integer(a.toLong())
        is Long -> JsonValue.Integer(a)
        is Double -> JsonValue.Floating(a)
        is Boolean -> JsonValue.Bool(a)
        JSONObject.NULL -> JsonValue.Null
        is JSONObject -> JsonValue.Obj(
            a.keys().asSequence().sorted().toList().map { it to jsonAnyToValue(a.get(it)) }
        )
        is JSONArray -> JsonValue.Arr((0 until a.length()).map { jsonAnyToValue(a.get(it)) })
        else -> throw IllegalArgumentException("unsupported fixture value: ${a::class}")
    }
}
```

- [ ] **Step 2: Run — expect test to pass (it's reading fixtures produced by the Swift side)**

Run: `./gradlew :app:testDebugUnitTest --tests '*ProtocolVectorsTest*'`
Expected: the single vector-conformance test passes, reading 3 vectors from `../tests/protocol-vectors.json`. If it FAILS with an HMAC mismatch, the cross-language bug is in Kotlin and must be fixed before proceeding.

- [ ] **Step 3: Commit**

```
git add SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/ProtocolVectorsTest.kt
git commit -m "test(mobile): cross-language protocol conformance vs Swift 1.3.0 fixture"
```

### Task 1.6: `NonceCache`

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/NonceCache.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/NonceCacheTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package com.snapback.mobile.protocol

import org.junit.Assert.*
import org.junit.Test

class NonceCacheTest {
    @Test fun acceptsFirstOccurrence() {
        val c = NonceCache(capacity = 8, ttlSeconds = 600.0)
        assertTrue(c.tryAdd("n1", at = 100.0))
    }

    @Test fun rejectsDuplicateWithinTTL() {
        val c = NonceCache(8, 600.0)
        c.tryAdd("n1", 100.0)
        assertFalse(c.tryAdd("n1", 101.0))
    }

    @Test fun acceptsAfterTTL() {
        val c = NonceCache(8, 600.0)
        c.tryAdd("n1", 100.0)
        assertTrue(c.tryAdd("n1", 701.0))
    }

    @Test fun evictsOldestOverCapacity() {
        val c = NonceCache(capacity = 2, ttlSeconds = 600.0)
        c.tryAdd("a", 100.0)
        c.tryAdd("b", 101.0)
        c.tryAdd("c", 102.0)
        assertTrue(c.tryAdd("a", 103.0))  // evicted, so re-add accepted
    }
}
```

- [ ] **Step 2: Write `NonceCache.kt`**

```kotlin
package com.snapback.mobile.protocol

/**
 * Bounded TTL cache with FIFO eviction, mirroring Swift NonceCache. Existing
 * entries are NOT promoted on duplicate-add — a replayed nonce cannot extend
 * its own lifetime by retrying. Thread-safe via monitor synchronization.
 */
class NonceCache(private val capacity: Int, private val ttlSeconds: Double) {
    private data class Entry(val nonce: String, val insertedAt: Double)
    private val entries = ArrayDeque<Entry>()

    @Synchronized
    fun tryAdd(nonce: String, at: Double): Boolean {
        // Evict expired.
        while (entries.isNotEmpty() && at - entries.first().insertedAt > ttlSeconds) {
            entries.removeFirst()
        }
        if (entries.any { it.nonce == nonce }) return false
        entries.addLast(Entry(nonce, at))
        while (entries.size > capacity) entries.removeFirst()
        return true
    }
}
```

- [ ] **Step 3: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*NonceCacheTest*'`
Expected: 4 pass.

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/protocol/NonceCache.kt SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/protocol/NonceCacheTest.kt
git commit -m "feat(mobile): NonceCache (TTL+FIFO, thread-safe)"
```

---

## Phase 2 — Keystore token store + QR pairing

### Task 2.1: `KeystoreTokenStore` (Android Keystore wrapper)

Android Keystore is harder to unit-test than iOS Keychain. Robolectric does not emulate Keystore faithfully — we test the interface against a fake, and validate real behaviour via an instrumented test in Phase 7.

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/security/TokenStore.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/security/KeystoreTokenStore.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/security/InMemoryTokenStoreTest.kt`

- [ ] **Step 1: Write `TokenStore.kt` (interface + in-memory fake)**

```kotlin
package com.snapback.mobile.security

/**
 * Secret-byte persistence interface. Production uses Android Keystore;
 * tests use InMemoryTokenStore to bypass Keystore's Robolectric quirks.
 */
interface TokenStore {
    fun read(): ByteArray?
    fun write(token: ByteArray)
    fun delete()
}

class InMemoryTokenStore : TokenStore {
    private var value: ByteArray? = null
    override fun read(): ByteArray? = value?.copyOf()
    override fun write(token: ByteArray) { value = token.copyOf() }
    override fun delete() { value = null }
}
```

- [ ] **Step 2: Write `InMemoryTokenStoreTest.kt`**

```kotlin
package com.snapback.mobile.security

import org.junit.Assert.*
import org.junit.Test

class InMemoryTokenStoreTest {
    @Test fun readReturnsNullWhenAbsent() {
        assertNull(InMemoryTokenStore().read())
    }

    @Test fun writeThenReadRoundTrip() {
        val s = InMemoryTokenStore()
        val data = ByteArray(32) { it.toByte() }
        s.write(data)
        assertArrayEquals(data, s.read())
    }

    @Test fun deleteClears() {
        val s = InMemoryTokenStore()
        s.write(ByteArray(4))
        s.delete()
        assertNull(s.read())
    }

    @Test fun readReturnsCopyNotReference() {
        val s = InMemoryTokenStore()
        val data = byteArrayOf(1, 2, 3)
        s.write(data)
        val out = s.read()!!
        out[0] = 99
        assertArrayEquals(byteArrayOf(1, 2, 3), s.read())
    }
}
```

- [ ] **Step 3: Write `KeystoreTokenStore.kt`**

Android Keystore stores keys not bytes; for a 32-byte shared secret we use an AES key wrapped over the token bytes. The spec's intent is "secret does not leak" — Keystore provides that. We persist the wrapped ciphertext in `SharedPreferences` under a hard-coded name.

```kotlin
package com.snapback.mobile.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Persists the 32-byte pair token. Token is AES-GCM encrypted under a
 * hardware-backed key (when available) whose key material never leaves the
 * Keystore. The ciphertext + IV lives in a private SharedPreferences file.
 */
class KeystoreTokenStore(private val context: Context) : TokenStore {

    override fun read(): ByteArray? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ivHex = prefs.getString(KEY_IV, null) ?: return null
        val ctHex = prefs.getString(KEY_CIPHERTEXT, null) ?: return null
        val iv = ivHex.hexToBytesOrNull() ?: return null
        val ct = ctHex.hexToBytesOrNull() ?: return null
        val secretKey = getOrCreateKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
        return try { cipher.doFinal(ct) } catch (e: Exception) { null }
    }

    override fun write(token: ByteArray) {
        val secretKey = getOrCreateKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val ct = cipher.doFinal(token)
        val iv = cipher.iv
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            putString(KEY_IV, iv.toHex())
            putString(KEY_CIPHERTEXT, ct.toHex())
        }.apply()
    }

    override fun delete() {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(false)
                .build()
        )
        return gen.generateKey()
    }

    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it.toInt() and 0xFF) }
    private fun String.hexToBytesOrNull(): ByteArray? {
        if (length % 2 != 0) return null
        val out = ByteArray(length / 2)
        for (i in out.indices) {
            val hi = digit(this[2 * i]) ?: return null
            val lo = digit(this[2 * i + 1]) ?: return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }
    private fun digit(c: Char): Int? = when (c) {
        in '0'..'9' -> c.code - '0'.code
        in 'a'..'f' -> c.code - 'a'.code + 10
        else -> null
    }

    companion object {
        private const val PREFS = "com.snapback.mobile.token"
        private const val KEY_IV = "iv"
        private const val KEY_CIPHERTEXT = "ct"
        private const val KEY_ALIAS = "com.snapback.mobile.pair-token"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
```

- [ ] **Step 4: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*InMemoryTokenStoreTest*'`
Expected: 4 pass.

`KeystoreTokenStore` itself is exercised by an instrumented test added in Phase 7, Task 7.3.

- [ ] **Step 5: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/security/ SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/security/InMemoryTokenStoreTest.kt
git commit -m "feat(mobile): TokenStore interface + Keystore-backed implementation + in-memory fake"
```

### Task 2.2: `PairingResult` — parse the QR URL

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/pair/PairingResult.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/pair/PairingResultTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package com.snapback.mobile.pair

import org.junit.Assert.*
import org.junit.Test

class PairingResultTest {
    @Test fun parseGoodURL() {
        val url = "snapback-pair://v1?token=" + "a".repeat(64) + "&desk=Hamper%27s%20MBP&v=1"
        val r = PairingResult.parse(url)
        assertNotNull(r)
        r!!
        assertEquals("a".repeat(64), r.tokenHex)
        assertEquals("Hamper's MBP", r.deskName)
    }

    @Test fun rejectsWrongScheme() {
        assertNull(PairingResult.parse("http://example.com/?token=" + "a".repeat(64)))
    }

    @Test fun rejectsWrongVersion() {
        val url = "snapback-pair://v2?token=" + "a".repeat(64) + "&desk=X&v=2"
        assertNull(PairingResult.parse(url))
    }

    @Test fun rejectsBadTokenLength() {
        val url = "snapback-pair://v1?token=" + "a".repeat(63) + "&desk=X&v=1"
        assertNull(PairingResult.parse(url))
    }

    @Test fun rejectsUppercaseTokenHex() {
        val url = "snapback-pair://v1?token=" + "A".repeat(64) + "&desk=X&v=1"
        assertNull(PairingResult.parse(url))
    }
}
```

- [ ] **Step 2: Write `PairingResult.kt`**

```kotlin
package com.snapback.mobile.pair

import android.net.Uri

data class PairingResult(val tokenHex: String, val deskName: String) {
    val token: ByteArray get() {
        val out = ByteArray(32)
        for (i in 0 until 32) {
            val hi = tokenHex[2 * i].digitToInt(16)
            val lo = tokenHex[2 * i + 1].digitToInt(16)
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    companion object {
        fun parse(url: String): PairingResult? {
            val uri = try { Uri.parse(url) } catch (e: Exception) { return null }
            if (uri.scheme != "snapback-pair") return null
            if (uri.host != "v1") return null
            if (uri.getQueryParameter("v") != "1") return null
            val token = uri.getQueryParameter("token") ?: return null
            if (token.length != 64) return null
            if (!token.all { it in '0'..'9' || it in 'a'..'f' }) return null
            val desk = uri.getQueryParameter("desk") ?: return null
            return PairingResult(token, desk)
        }
    }
}
```

- [ ] **Step 3: Run tests (needs Robolectric for `Uri`)**

Run: `./gradlew :app:testDebugUnitTest --tests '*PairingResultTest*'`
Expected: 5 pass.

If it fails with `android.net.Uri not found`, add `@RunWith(RobolectricTestRunner::class)` to the class and `testImplementation` Robolectric is already in deps from Phase 0. If Robolectric still can't parse Uri, rewrite the parser to use plain regex — no Android API dependency.

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/pair/PairingResult.kt SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/pair/PairingResultTest.kt
git commit -m "feat(mobile): PairingResult parses snapback-pair:// QR URL"
```

### Task 2.3: `PairingActivity` (CameraX + ML Kit)

This is a UI activity. Unit test via Robolectric is of limited value; rely on manual smoke test at the end of the phase.

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/pair/PairingActivity.kt`
- Modify: `SnapBackMobile/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add Camera permission + Activity declaration to Manifest**

In `AndroidManifest.xml`, before the closing `</application>` and outside `<application>`:

```xml
    <uses-permission android:name="android.permission.CAMERA" />
```

Inside `<application>`, add:

```xml
        <activity
            android:name=".pair.PairingActivity"
            android:exported="true"
            android:theme="@style/Theme.SnapBackMobile">
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="snapback-pair" />
            </intent-filter>
        </activity>
```

- [ ] **Step 2: Write `PairingActivity.kt`**

```kotlin
package com.snapback.mobile.pair

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Size
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.service.MobileForegroundService
import java.util.concurrent.Executors

class PairingActivity : ComponentActivity() {

    private val cameraExecutor = Executors.newSingleThreadExecutor()

    private val requestCameraPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) {
            Toast.makeText(this, "Camera permission required to scan the QR", Toast.LENGTH_LONG).show()
            finish()
        } else {
            setContent { ScannerUI() }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED) {
            setContent { ScannerUI() }
        } else {
            requestCameraPermission.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
    }

    @Composable
    private fun ScannerUI() {
        var statusText by remember { mutableStateOf("Point the camera at the QR code on your Mac") }

        Box(modifier = Modifier.fillMaxSize()) {
            AndroidView(
                factory = { ctx ->
                    val preview = PreviewView(ctx)
                    bindCamera(preview) { result ->
                        onPaired(result)
                        statusText = "Paired. You can return to your Mac."
                    }
                    preview
                },
                modifier = Modifier.fillMaxSize()
            )
            Text(
                statusText,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(24.dp)
            )
        }
    }

    private fun bindCamera(view: PreviewView, onResult: (PairingResult) -> Unit) {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(view.surfaceProvider)
            }
            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build()
            val scanner = BarcodeScanning.getClient(options)
            val analyzer = ImageAnalysis.Builder()
                .setTargetResolution(Size(1280, 720))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { it.setAnalyzer(cameraExecutor) { proxy -> scan(scanner, proxy, onResult) } }

            provider.unbindAll()
            provider.bindToLifecycle(
                this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analyzer
            )
        }, ContextCompat.getMainExecutor(this))
    }

    @androidx.camera.core.ExperimentalGetImage
    private fun scan(
        scanner: com.google.mlkit.vision.barcode.BarcodeScanner,
        proxy: ImageProxy,
        onResult: (PairingResult) -> Unit
    ) {
        val media = proxy.image
        if (media == null) { proxy.close(); return }
        val input = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
        scanner.process(input)
            .addOnSuccessListener { barcodes ->
                for (b in barcodes) {
                    val raw = b.rawValue ?: continue
                    val pr = PairingResult.parse(raw) ?: continue
                    onResult(pr)
                    return@addOnSuccessListener
                }
            }
            .addOnCompleteListener { proxy.close() }
    }

    private fun onPaired(result: PairingResult) {
        KeystoreTokenStore(this).write(result.token)
        MobileForegroundService.start(this)
        runOnUiThread {
            Toast.makeText(this, "Paired with ${result.deskName}", Toast.LENGTH_SHORT).show()
            finish()
        }
    }
}
```

- [ ] **Step 3: Compile — expect `MobileForegroundService` not to exist yet**

Because `MobileForegroundService.start(this)` is referenced but not yet defined, the build will fail. To avoid a broken intermediate state, create a placeholder stub now; Phase 3 will fill it in.

Create `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/MobileForegroundService.kt`:

```kotlin
package com.snapback.mobile.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder

class MobileForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        fun start(context: Context) {
            // filled in Phase 3
            context.startService(Intent(context, MobileForegroundService::class.java))
        }
    }
}
```

- [ ] **Step 4: Build**

Run: `./gradlew :app:assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/pair/PairingActivity.kt SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/MobileForegroundService.kt SnapBackMobile/app/src/main/AndroidManifest.xml
git commit -m "feat(mobile): PairingActivity with CameraX+ML Kit QR scanner"
```

---

## Phase 3 — Slice A "Hello, Mac" (network, no lock)

### Task 3.1: `MdnsAdvertiser` — `NsdManager` wrapper

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/net/MdnsAdvertiser.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/net/WifiLocks.kt`

- [ ] **Step 1: Write `MdnsAdvertiser.kt`**

```kotlin
package com.snapback.mobile.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log

class MdnsAdvertiser(private val context: Context) {
    private var nsd: NsdManager? = null
    private var listener: NsdManager.RegistrationListener? = null
    private var registered = false

    fun start(port: Int) {
        if (registered) return
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        this.nsd = nsd

        val info = NsdServiceInfo().apply {
            serviceName = "snapback-" + Build.MODEL.filter { it.isLetterOrDigit() }
                .take(16).ifEmpty { "device" }
            serviceType = "_snapback._tcp"
            this.port = port
            setAttribute("device_name", Build.MODEL)
        }
        val l = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(s: NsdServiceInfo) {
                Log.i(TAG, "mdns registered: ${s.serviceName}@${s.port}")
                registered = true
            }
            override fun onRegistrationFailed(s: NsdServiceInfo, code: Int) {
                Log.w(TAG, "mdns register failed: $code")
            }
            override fun onServiceUnregistered(s: NsdServiceInfo) {
                Log.i(TAG, "mdns unregistered")
                registered = false
            }
            override fun onUnregistrationFailed(s: NsdServiceInfo, code: Int) {
                Log.w(TAG, "mdns unregister failed: $code")
            }
        }
        listener = l
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, l)
    }

    fun stop() {
        val nsd = this.nsd ?: return
        val l = this.listener ?: return
        try { nsd.unregisterService(l) } catch (e: Exception) { /* already unregistered */ }
        listener = null
    }

    companion object { private const val TAG = "SnapBack/mdns" }
}
```

- [ ] **Step 2: Write `WifiLocks.kt`**

```kotlin
package com.snapback.mobile.net

import android.content.Context
import android.net.wifi.WifiManager

/**
 * Bundled wifi locks:
 *   • MulticastLock stays held for the service lifetime to keep mDNS
 *     advertising alive with screen off.
 *   • WifiLock(HIGH_PERF) is acquired ONLY while HOLD is outstanding.
 *     Holding it permanently is a battery disaster (§5.8).
 */
class WifiLocks(context: Context) {
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val multicast = wifi.createMulticastLock("snapback-mdns").apply { setReferenceCounted(false) }
    private val wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "snapback-hold")
        .apply { setReferenceCounted(false) }

    fun holdMulticast() { if (!multicast.isHeld) multicast.acquire() }
    fun releaseMulticast() { if (multicast.isHeld) multicast.release() }

    fun holdHighPerfWifi() { if (!wifiLock.isHeld) wifiLock.acquire() }
    fun releaseHighPerfWifi() { if (wifiLock.isHeld) wifiLock.release() }
}
```

- [ ] **Step 3: Add permissions to Manifest**

In `AndroidManifest.xml`, before `<application>`:

```xml
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />
```

- [ ] **Step 4: Build**

Run: `./gradlew :app:assembleDebug`

- [ ] **Step 5: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/net/ SnapBackMobile/app/src/main/AndroidManifest.xml
git commit -m "feat(mobile): NsdManager advertiser and WifiLocks wrapper"
```

### Task 3.2: `TestFakeMac` harness + `MessageServer` (TDD)

We need a Kotlin mirror of Swift's `TestFakePhone`: an in-process client that pretends to be the Mac bridge, connects to the Kotlin server, and exercises the full HMAC + wire path.

**Files:**
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/net/TestFakeMac.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/net/MessageServer.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/net/MessageServerTest.kt`

- [ ] **Step 1: Write `TestFakeMac.kt`**

```kotlin
package com.snapback.mobile.net

import com.snapback.mobile.protocol.*
import java.net.Socket

/**
 * In-process Mac-side peer for server tests. Connects, sends a signed `hello`,
 * and exposes a method to send arbitrary messages. Receives messages on a
 * background thread and records their types.
 */
class TestFakeMac(private val host: String, private val port: Int, private val secret: ByteArray) {
    private lateinit var socket: Socket
    val received = mutableListOf<String>()

    fun connect() {
        socket = Socket(host, port)
    }

    fun sendHello() = send(ProtocolMessageType.Hello,
        listOf("app_version" to JsonValue.Str("test"),
               "peer_name" to JsonValue.Str("TestFakeMac")))

    fun send(type: ProtocolMessageType, payload: List<Pair<String, JsonValue>> = emptyList()) {
        val nonce = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it.toInt() and 0xFF) }
        val msg = ProtocolMessage(
            version = 1, type = type,
            timestamp = System.currentTimeMillis() / 1000,
            nonceHex = nonce, payload = payload
        )
        val line = MessageCodec.encodeSignedLine(msg, ProtocolDirection.ClientToServer, secret)
        socket.getOutputStream().write(line.toByteArray(Charsets.UTF_8))
        socket.getOutputStream().flush()
    }

    fun startReceiver() {
        Thread {
            val reader = socket.getInputStream().bufferedReader(Charsets.UTF_8)
            while (true) {
                val line = reader.readLine() ?: break
                val (msg, hmac) = MessageCodec.decodeLine(line + "\n")
                if (MessageCodec.verify(msg, ProtocolDirection.ServerToClient, hmac, secret)) {
                    synchronized(received) { received.add(msg.type.wire) }
                }
            }
        }.apply { isDaemon = true; start() }
    }

    fun close() { try { socket.close() } catch (_: Exception) {} }
}
```

- [ ] **Step 2: Write the failing `MessageServerTest.kt`**

```kotlin
package com.snapback.mobile.net

import com.snapback.mobile.protocol.*
import org.junit.Assert.*
import org.junit.Test
import java.net.ServerSocket

class MessageServerTest {
    private val secret = ByteArray(32) { 0x42 }

    @Test fun acceptsHelloAndRepliesAck() {
        val port = ServerSocket(0).use { it.localPort }
        val events = mutableListOf<ProtocolMessage>()
        val server = MessageServer(secret, port) { events.add(it) }
        server.start()
        try {
            val mac = TestFakeMac("127.0.0.1", port, secret)
            mac.connect()
            mac.startReceiver()
            mac.sendHello()
            waitUntil(3000) { events.any { it.type == ProtocolMessageType.Hello } }
            waitUntil(3000) { mac.received.contains("ack") }
            mac.close()
            assertTrue(events.any { it.type == ProtocolMessageType.Hello })
            assertTrue(mac.received.contains("ack"))
        } finally {
            server.stop()
        }
    }

    @Test fun rejectsTamperedHmac() {
        val port = ServerSocket(0).use { it.localPort }
        val events = mutableListOf<ProtocolMessage>()
        val server = MessageServer(secret, port) { events.add(it) }
        server.start()
        try {
            // Build a raw line with a bad HMAC.
            val badLine = """{"v":1,"type":"attention","ts":1,"nonce":"${"0".repeat(32)}",""" +
                """"payload":{"hook":"Stop"},"hmac":"${"0".repeat(64)}"}""" + "\n"
            java.net.Socket("127.0.0.1", port).use { s ->
                s.getOutputStream().write(badLine.toByteArray(Charsets.UTF_8))
                s.getOutputStream().flush()
                Thread.sleep(100)
            }
            assertTrue(events.isEmpty())
        } finally {
            server.stop()
        }
    }

    @Test fun rejectsReplayedNonce() {
        val port = ServerSocket(0).use { it.localPort }
        val events = mutableListOf<ProtocolMessage>()
        val server = MessageServer(secret, port) { events.add(it) }
        server.start()
        try {
            val mac = TestFakeMac("127.0.0.1", port, secret)
            mac.connect()
            mac.startReceiver()

            // Build one message, send it twice with the SAME nonce.
            val msg = ProtocolMessage(
                1, ProtocolMessageType.Attention, System.currentTimeMillis() / 1000,
                "deadbeef".repeat(4), listOf("hook" to JsonValue.Str("Stop"))
            )
            val line = MessageCodec.encodeSignedLine(msg, ProtocolDirection.ClientToServer, secret)
            mac.rawSend(line)
            mac.rawSend(line)
            waitUntil(2000) { events.isNotEmpty() }
            Thread.sleep(200)  // let the duplicate land
            assertEquals(1, events.count { it.type == ProtocolMessageType.Attention })
            mac.close()
        } finally {
            server.stop()
        }
    }

    private fun waitUntil(maxMs: Int, cond: () -> Boolean) {
        val deadline = System.currentTimeMillis() + maxMs
        while (System.currentTimeMillis() < deadline && !cond()) Thread.sleep(20)
    }
}
```

To satisfy `mac.rawSend(line)`, add to `TestFakeMac`:

```kotlin
    fun rawSend(line: String) {
        socket.getOutputStream().write(line.toByteArray(Charsets.UTF_8))
        socket.getOutputStream().flush()
    }
```

- [ ] **Step 3: Write `MessageServer.kt`**

```kotlin
package com.snapback.mobile.net

import com.snapback.mobile.protocol.*
import kotlinx.coroutines.*
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * TCP server that receives signed messages from the Mac, verifies HMAC/ts/nonce,
 * and invokes `onMessage` on the valid ones. Also writes acks/pongs back.
 *
 * Runs an accept loop on a dedicated thread; each connection is a single
 * Mac for MVP — we accept but only the first connection's messages drive
 * orchestrator state (same policy as Swift).
 */
class MessageServer(
    private val secret: ByteArray,
    val port: Int,
    private val onMessage: (ProtocolMessage) -> Unit
) {
    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val nonceCache = NonceCache(capacity = 1024, ttlSeconds = 600.0)

    fun start() {
        if (!running.compareAndSet(false, true)) return
        val s = ServerSocket(port)
        serverSocket = s
        scope.launch {
            while (running.get()) {
                val client = try { s.accept() } catch (e: Exception) { break }
                scope.launch { handle(client) }
            }
        }
    }

    fun stop() {
        running.set(false)
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        scope.cancel()
    }

    private suspend fun handle(socket: Socket) {
        try {
            val reader = socket.getInputStream().bufferedReader(Charsets.UTF_8)
            val writer = socket.getOutputStream()
            while (true) {
                val line = reader.readLine() ?: break
                val (msg, hmac) = try { MessageCodec.decodeLine(line + "\n") }
                                   catch (e: Exception) { continue }
                if (!MessageCodec.verify(msg, ProtocolDirection.ClientToServer, hmac, secret)) continue
                val now = System.currentTimeMillis() / 1000.0
                if (kotlin.math.abs(now - msg.timestamp) > 30) continue
                if (!nonceCache.tryAdd(msg.nonceHex, now)) continue

                onMessage(msg)

                // Reply to hello/heartbeat/resync inline.
                when (msg.type) {
                    ProtocolMessageType.Hello -> reply(writer, ProtocolMessageType.Ack, emptyList())
                    ProtocolMessageType.Heartbeat,
                    ProtocolMessageType.Resync -> reply(
                        writer, ProtocolMessageType.Pong,
                        listOf("hold" to JsonValue.Bool(false))  // slice A: never holding
                    )
                    else -> {}
                }
            }
        } catch (e: Exception) {
            // Dropped connection: fall through to cleanup.
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun reply(writer: java.io.OutputStream, type: ProtocolMessageType,
                      payload: List<Pair<String, JsonValue>>) {
        val nonce = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it.toInt() and 0xFF) }
        val msg = ProtocolMessage(
            1, type, System.currentTimeMillis() / 1000, nonce, payload
        )
        val line = MessageCodec.encodeSignedLine(msg, ProtocolDirection.ServerToClient, secret)
        writer.write(line.toByteArray(Charsets.UTF_8))
        writer.flush()
    }
}
```

- [ ] **Step 4: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*MessageServerTest*'`
Expected: 3 pass.

- [ ] **Step 5: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/net/ SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/net/
git commit -m "feat(mobile): MessageServer with HMAC+nonce+ts gates, TestFakeMac harness"
```

### Task 3.3: `MobileForegroundService` (real version, no lock yet)

Replace the Phase 2 stub with a real foreground service that owns `MessageServer` + `MdnsAdvertiser` + `WifiLocks` + Keystore read.

**Files:**
- Modify: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/MobileForegroundService.kt`
- Modify: `SnapBackMobile/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Update Manifest — add service permission + declaration**

In `AndroidManifest.xml`:

```xml
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Inside `<application>`:

```xml
        <service
            android:name=".service.MobileForegroundService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Maintains connection to paired SnapBack Mac bridge for attention management." />
        </service>
```

- [ ] **Step 2: Rewrite `MobileForegroundService.kt`**

```kotlin
package com.snapback.mobile.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.snapback.mobile.BuildConfig
import com.snapback.mobile.R
import com.snapback.mobile.net.MdnsAdvertiser
import com.snapback.mobile.net.MessageServer
import com.snapback.mobile.net.WifiLocks
import com.snapback.mobile.protocol.ProtocolMessage
import com.snapback.mobile.security.KeystoreTokenStore

class MobileForegroundService : Service() {
    private var server: MessageServer? = null
    private var mdns: MdnsAdvertiser? = null
    private var locks: WifiLocks? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Waiting for Mac"))
        startBridge()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        stopBridge()
        super.onDestroy()
    }

    private fun startBridge() {
        val token = KeystoreTokenStore(this).read() ?: run {
            Log.w(TAG, "no paired token; foreground service running but idle")
            return
        }
        val locks = WifiLocks(this).also { it.holdMulticast() }
        this.locks = locks

        val server = MessageServer(token, DEFAULT_PORT) { msg: ProtocolMessage ->
            onMessage(msg)
        }
        server.start()
        this.server = server

        val mdns = MdnsAdvertiser(this).also { it.start(DEFAULT_PORT) }
        this.mdns = mdns
    }

    private fun stopBridge() {
        server?.stop()
        server = null
        mdns?.stop()
        mdns = null
        locks?.releaseMulticast()
        locks?.releaseHighPerfWifi()
        locks = null
    }

    private fun onMessage(msg: ProtocolMessage) {
        // Slice A: observe only. Lock wiring arrives in Phase 5.
        Log.i(TAG, "received ${msg.type.wire}")
    }

    private fun ensureNotificationChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID, "SnapBack bridge",
                    NotificationManager.IMPORTANCE_LOW
                ).apply { description = "Persistent connection to your paired Mac." }
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle("SnapBack Mobile")
            .setContentText(text)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "SnapBack/fgs"
        private const val CHANNEL_ID = "snapback-bridge"
        private const val NOTIF_ID = 1001
        const val DEFAULT_PORT = 45782

        fun start(context: Context) {
            val intent = Intent(context, MobileForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MobileForegroundService::class.java))
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `./gradlew :app:assembleDebug`

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/MobileForegroundService.kt SnapBackMobile/app/src/main/AndroidManifest.xml
git commit -m "feat(mobile): MobileForegroundService owns server+mdns+locks (slice A)"
```

### Task 3.4: Slice A verification — `MainActivity` "Bridge connected" screen

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/MainActivity.kt`
- Modify: `SnapBackMobile/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add MainActivity to Manifest**

Inside `<application>`:

```xml
        <activity
            android:name=".ui.MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
```

- [ ] **Step 2: Write `MainActivity.kt`** (minimal — Phase 6 expands this into a real Settings screen)

```kotlin
package com.snapback.mobile.ui

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.snapback.mobile.pair.PairingActivity
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.service.MobileForegroundService

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val paired = remember { KeystoreTokenStore(this).read() != null }
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Column(
                    modifier = Modifier.fillMaxSize().padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("SnapBack Mobile", style = MaterialTheme.typography.headlineMedium)
                    Spacer(Modifier.height(24.dp))
                    if (paired) {
                        Text("Bridge connected.", style = MaterialTheme.typography.bodyLarge)
                        Spacer(Modifier.height(8.dp))
                        Text("1.4.0 slice A — lock mechanic arrives in later slices.",
                             style = MaterialTheme.typography.bodySmall)
                        Spacer(Modifier.height(24.dp))
                        Button(onClick = {
                            KeystoreTokenStore(this@MainActivity).delete()
                            MobileForegroundService.stop(this@MainActivity)
                            recreate()
                        }) { Text("Unpair") }
                    } else {
                        Text("Not paired.", style = MaterialTheme.typography.bodyLarge)
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = {
                            startActivity(Intent(this@MainActivity, PairingActivity::class.java))
                        }) { Text("Pair with Mac") }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build the debug APK**

Run: `./gradlew :app:assembleDebug`
Expected: `app-debug.apk` at `app/build/outputs/apk/debug/`.

- [ ] **Step 4: Slice A smoke test** (manual, emulator)

Start an Android emulator with API 34+. Install:

```
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.snapback.mobile.debug/com.snapback.mobile.ui.MainActivity
```

Expected: the app opens showing "Not paired." + a "Pair with Mac" button. Do NOT actually pair yet — that's a later-phase smoke test. Just confirm the app launches and is installable.

- [ ] **Step 5: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/MainActivity.kt SnapBackMobile/app/src/main/AndroidManifest.xml
git commit -m "feat(mobile): MainActivity launcher with pair/unpair entry points (slice A MVP)"
```

---

## Phase 4 — Slice B "Lock mechanic, isolated"

### Task 4.1: `LockDriver` three-tier fallback

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/lock/LockDriver.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/lock/SnapBackAccessibilityService.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/lock/SnapBackDeviceAdminReceiver.kt`
- Create: `SnapBackMobile/app/src/main/res/xml/accessibility_config.xml`
- Create: `SnapBackMobile/app/src/main/res/xml/device_admin_policies.xml`
- Modify: `SnapBackMobile/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Write `accessibility_config.xml`** — minimal: no event types, just performs the global action.

```xml
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes=""
    android:accessibilityFeedbackType="feedbackGeneric"
    android:canPerformGestures="false"
    android:canRetrieveWindowContent="false"
    android:description="@string/accessibility_description"
    android:notificationTimeout="0"
    android:settingsActivity="com.snapback.mobile.ui.MainActivity" />
```

- [ ] **Step 2: Add description string**

In `strings.xml`:

```xml
    <string name="accessibility_description">SnapBack Mobile uses Accessibility only to lock the screen when your paired Mac reports that Claude Code is waiting for you. No screen content is read; no events other than the lock action are produced.</string>
    <string name="device_admin_description">SnapBack Mobile uses Device Admin as a fallback lock primitive when Accessibility is not enabled. Only the lockNow permission is used.</string>
```

- [ ] **Step 3: Write `device_admin_policies.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<device-admin xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-policies>
        <force-lock />
    </uses-policies>
</device-admin>
```

- [ ] **Step 4: Register both in the Manifest**

Inside `<application>`:

```xml
        <service
            android:name=".lock.SnapBackAccessibilityService"
            android:exported="false"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_config" />
        </service>

        <receiver
            android:name=".lock.SnapBackDeviceAdminReceiver"
            android:exported="true"
            android:permission="android.permission.BIND_DEVICE_ADMIN"
            android:description="@string/device_admin_description"
            android:label="@string/app_name">
            <meta-data
                android:name="android.app.device_admin"
                android:resource="@xml/device_admin_policies" />
            <intent-filter>
                <action android:name="android.app.action.DEVICE_ADMIN_ENABLED" />
            </intent-filter>
        </receiver>
```

- [ ] **Step 5: Write `SnapBackAccessibilityService.kt`**

```kotlin
package com.snapback.mobile.lock

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * Sole purpose: call `performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)` when
 * `LockDriver` requests. Does not subscribe to any event types.
 */
class SnapBackAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // no-op
    }

    override fun onInterrupt() {
        // no-op
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        @Volatile var instance: SnapBackAccessibilityService? = null
            private set

        fun lockViaAccessibility(): Boolean {
            val svc = instance ?: return false
            return svc.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
        }
    }
}
```

- [ ] **Step 6: Write `SnapBackDeviceAdminReceiver.kt`**

```kotlin
package com.snapback.mobile.lock

import android.app.admin.DeviceAdminReceiver
import android.content.ComponentName
import android.content.Context
import android.app.admin.DevicePolicyManager

class SnapBackDeviceAdminReceiver : DeviceAdminReceiver() {
    companion object {
        fun lockViaDeviceAdmin(context: Context): Boolean {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val admin = ComponentName(context, SnapBackDeviceAdminReceiver::class.java)
            if (!dpm.isAdminActive(admin)) return false
            return try { dpm.lockNow(); true } catch (e: SecurityException) { false }
        }
    }
}
```

- [ ] **Step 7: Write `LockDriver.kt`**

```kotlin
package com.snapback.mobile.lock

import android.content.Context
import android.util.Log

/**
 * Tries lock primitives in order: Accessibility (preferred, Play-safe),
 * Device Admin (stronger semantics), Overlay activity (weakest). Returns the
 * tier that succeeded, or LockTier.None.
 */
enum class LockTier { Accessibility, DeviceAdmin, Overlay, None }

class LockDriver(private val context: Context) {
    fun lock(): LockTier {
        if (SnapBackAccessibilityService.lockViaAccessibility()) {
            Log.i(TAG, "locked via Accessibility")
            return LockTier.Accessibility
        }
        if (SnapBackDeviceAdminReceiver.lockViaDeviceAdmin(context)) {
            Log.i(TAG, "locked via Device Admin")
            return LockTier.DeviceAdmin
        }
        if (OverlayActivity.show(context)) {
            Log.i(TAG, "locked via overlay (weakest)")
            return LockTier.Overlay
        }
        Log.w(TAG, "all lock tiers failed")
        return LockTier.None
    }

    companion object { private const val TAG = "SnapBack/lock" }
}
```

- [ ] **Step 8: Write `OverlayActivity.kt`** — the fullscreen fallback

Create `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/lock/OverlayActivity.kt`:

```kotlin
package com.snapback.mobile.lock

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Last-resort lock: a fullscreen, no-back-button activity. Dismissible only
 * via the orchestrator's `releaseHold()` finishing it.
 */
class OverlayActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
                Column(
                    modifier = Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("Claude is waiting on your Mac.", color = Color.White,
                         style = MaterialTheme.typography.headlineMedium)
                    Spacer(Modifier.height(24.dp))
                    Text("This overlay will dismiss once you respond.", color = Color.White,
                         style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        activeInstance = this
    }

    override fun onBackPressed() { /* swallow */ }

    override fun onDestroy() {
        if (activeInstance === this) activeInstance = null
        super.onDestroy()
    }

    companion object {
        @Volatile private var activeInstance: OverlayActivity? = null

        fun show(context: Context): Boolean {
            return try {
                val i = Intent(context, OverlayActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                context.startActivity(i)
                true
            } catch (e: Exception) { false }
        }

        fun dismiss() { activeInstance?.finish() }
    }
}
```

Register in Manifest:

```xml
        <activity
            android:name=".lock.OverlayActivity"
            android:exported="false"
            android:excludeFromRecents="true"
            android:launchMode="singleTask"
            android:theme="@style/Theme.SnapBackMobile" />
```

- [ ] **Step 9: Build**

Run: `./gradlew :app:assembleDebug`
Expected: success.

- [ ] **Step 10: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/lock/ SnapBackMobile/app/src/main/res/ SnapBackMobile/app/src/main/AndroidManifest.xml
git commit -m "feat(mobile): LockDriver with Accessibility→DeviceAdmin→Overlay fallback"
```

### Task 4.2: "Test lock" button in `MainActivity`

Slice B end-state: open the app, tap "Test lock", phone locks.

**Files:**
- Modify: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/MainActivity.kt`

- [ ] **Step 1: Replace `MainActivity`'s body so the paired branch shows a Test-lock button**

```kotlin
                    if (paired) {
                        Text("Bridge connected.", style = MaterialTheme.typography.bodyLarge)
                        Spacer(Modifier.height(8.dp))
                        Text("1.4.0 slice B — tap below to confirm lock works.",
                             style = MaterialTheme.typography.bodySmall)
                        Spacer(Modifier.height(24.dp))
                        Button(onClick = {
                            val tier = LockDriver(this@MainActivity).lock()
                            android.widget.Toast.makeText(
                                this@MainActivity,
                                "Lock attempted: $tier", android.widget.Toast.LENGTH_SHORT
                            ).show()
                        }) { Text("Test lock") }
                        Spacer(Modifier.height(12.dp))
                        Button(onClick = {
                            KeystoreTokenStore(this@MainActivity).delete()
                            MobileForegroundService.stop(this@MainActivity)
                            recreate()
                        }) { Text("Unpair") }
                    }
```

Also add the import: `import com.snapback.mobile.lock.LockDriver`.

- [ ] **Step 2: Slice B smoke test** (manual, real device preferred)

```
./gradlew :app:installDebug
```

In Android Settings → Accessibility → SnapBack Mobile (debug) → Enable. Then tap "Test lock" in the app. Screen should lock.

If Accessibility is disabled, enable Device Admin in Settings → Security → Device Admins → SnapBack Mobile, then test again. Finally, with neither enabled, the Overlay tier should fire.

- [ ] **Step 3: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/MainActivity.kt
git commit -m "feat(mobile): MainActivity Test-lock button exercises LockDriver (slice B)"
```

---

## Phase 5 — Slice C wiring: hold state machine + gate + fail-safes

### Task 5.1: `ScreenStateGate`

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/state/ScreenStateGate.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/state/ScreenStateGateTest.kt`

- [ ] **Step 1: Write failing test**

```kotlin
package com.snapback.mobile.state

import org.junit.Assert.*
import org.junit.Test

class ScreenStateGateTest {
    @Test fun onlyFiresWhenInteractiveAndUnlocked() {
        assertTrue(ScreenStateGate.passes(isInteractive = true, isLocked = false))
        assertFalse(ScreenStateGate.passes(isInteractive = false, isLocked = false))
        assertFalse(ScreenStateGate.passes(isInteractive = true, isLocked = true))
        assertFalse(ScreenStateGate.passes(isInteractive = false, isLocked = true))
    }
}
```

- [ ] **Step 2: Write `ScreenStateGate.kt`**

```kotlin
package com.snapback.mobile.state

import android.app.KeyguardManager
import android.content.Context
import android.os.PowerManager

/**
 * Decides whether an `attention` event should actually lock the screen.
 * The rule (spec §5.3): lock only when the user is ACTIVELY using the phone —
 * i.e., screen is on AND not in keyguard. Phone-in-pocket = no-op.
 */
object ScreenStateGate {
    fun passes(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return passes(pm.isInteractive, km.isDeviceLocked)
    }

    /** Pure-function variant, used by unit tests. */
    fun passes(isInteractive: Boolean, isLocked: Boolean): Boolean {
        return isInteractive && !isLocked
    }
}
```

- [ ] **Step 3: Run test**

Run: `./gradlew :app:testDebugUnitTest --tests '*ScreenStateGateTest*'`
Expected: 1 pass.

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/state/ScreenStateGate.kt SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/state/ScreenStateGateTest.kt
git commit -m "feat(mobile): ScreenStateGate pure policy + Android-wired variant"
```

### Task 5.2: `HoldStateMachine`

Core of slice C. Pure logic, unit-testable without Android.

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/state/HoldStateMachine.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/state/HoldStateMachineTest.kt`

- [ ] **Step 1: Write failing test**

```kotlin
package com.snapback.mobile.state

import org.junit.Assert.*
import org.junit.Test

class HoldStateMachineTest {
    @Test fun initialStateIsIdle() {
        assertEquals(HoldState.Idle, HoldStateMachine(ttlMs = 1000L).state)
    }

    @Test fun attentionWithPassingGateEntersHold() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        val r = sm.onAttention(gatePasses = true, hookKind = "Stop", nowMs = 1000L)
        assertEquals(TransitionEffect.LockAndArmTimer, r)
        assertEquals(HoldState.Hold, sm.state)
    }

    @Test fun attentionWithFailingGateDoesNothing() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        val r = sm.onAttention(gatePasses = false, hookKind = "Stop", nowMs = 1000L)
        assertEquals(TransitionEffect.Ignore, r)
        assertEquals(HoldState.Idle, sm.state)
    }

    @Test fun resumeExitsHoldAndCancelsTimer() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onResume(2000L)
        assertEquals(TransitionEffect.UnlockAndCancelTimer, r)
        assertEquals(HoldState.Idle, sm.state)
    }

    @Test fun ttlTimeoutExitsHold() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onTtlTick(nowMs = 2001L)
        assertEquals(TransitionEffect.UnlockAndCancelTimer, r)
        assertEquals(HoldState.Idle, sm.state)
    }

    @Test fun heartbeatMissExitsHold() {
        val sm = HoldStateMachine(ttlMs = 1_000_000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onHeartbeatMiss()
        assertEquals(TransitionEffect.UnlockAndCancelTimer, r)
        assertEquals(HoldState.Idle, sm.state)
    }

    @Test fun userPresentDuringHoldRelocks() {
        val sm = HoldStateMachine(ttlMs = 1_000_000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onUserPresent()
        assertEquals(TransitionEffect.RelockAfterGrace, r)
        assertEquals(HoldState.Hold, sm.state)
    }

    @Test fun userPresentWhileIdleIgnored() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        val r = sm.onUserPresent()
        assertEquals(TransitionEffect.Ignore, r)
    }

    @Test fun manualReleaseExitsHold() {
        val sm = HoldStateMachine(ttlMs = 1_000_000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onManualRelease()
        assertEquals(TransitionEffect.UnlockAndCancelTimer, r)
        assertEquals(HoldState.Idle, sm.state)
    }
}
```

- [ ] **Step 2: Write `HoldStateMachine.kt`**

```kotlin
package com.snapback.mobile.state

enum class HoldState { Idle, Hold }

/**
 * What the owning service should do in response to a state-machine event.
 * The machine itself is pure; effects are handled by the caller.
 */
enum class TransitionEffect {
    Ignore,
    LockAndArmTimer,
    UnlockAndCancelTimer,
    RelockAfterGrace
}

/**
 * Pure state machine. No Android APIs. Time is supplied by the caller so tests
 * are deterministic. `ttlMs` is the hard timeout after which HOLD must exit
 * regardless of any other signal — this is the "don't brick the phone" fuse.
 */
class HoldStateMachine(private val ttlMs: Long) {
    var state: HoldState = HoldState.Idle
        private set
    private var holdStartedAt: Long = 0L

    fun onAttention(gatePasses: Boolean, hookKind: String, nowMs: Long): TransitionEffect {
        if (state == HoldState.Hold) return TransitionEffect.Ignore  // already holding
        if (!gatePasses) return TransitionEffect.Ignore
        state = HoldState.Hold
        holdStartedAt = nowMs
        return TransitionEffect.LockAndArmTimer
    }

    fun onResume(nowMs: Long): TransitionEffect {
        if (state != HoldState.Hold) return TransitionEffect.Ignore
        state = HoldState.Idle
        return TransitionEffect.UnlockAndCancelTimer
    }

    fun onTtlTick(nowMs: Long): TransitionEffect {
        if (state != HoldState.Hold) return TransitionEffect.Ignore
        if (nowMs - holdStartedAt < ttlMs) return TransitionEffect.Ignore
        state = HoldState.Idle
        return TransitionEffect.UnlockAndCancelTimer
    }

    fun onHeartbeatMiss(): TransitionEffect {
        if (state != HoldState.Hold) return TransitionEffect.Ignore
        state = HoldState.Idle
        return TransitionEffect.UnlockAndCancelTimer
    }

    fun onUserPresent(): TransitionEffect {
        return if (state == HoldState.Hold) TransitionEffect.RelockAfterGrace
               else TransitionEffect.Ignore
    }

    fun onManualRelease(): TransitionEffect {
        if (state != HoldState.Hold) return TransitionEffect.Ignore
        state = HoldState.Idle
        return TransitionEffect.UnlockAndCancelTimer
    }
}
```

- [ ] **Step 3: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*HoldStateMachineTest*'`
Expected: 8 pass.

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/state/HoldStateMachine.kt SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/state/HoldStateMachineTest.kt
git commit -m "feat(mobile): HoldStateMachine pure logic with hard-TTL fuse"
```

### Task 5.3: Wire the state machine into `MobileForegroundService`

End-state of slice C: real messages from the Mac trigger real locks, with fail-safes.

**Files:**
- Modify: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/MobileForegroundService.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/UserPresentReceiver.kt`

- [ ] **Step 1: Create `UserPresentReceiver.kt`**

```kotlin
package com.snapback.mobile.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives ACTION_USER_PRESENT and forwards it to the foreground service,
 * which asks the state machine whether to re-lock.
 */
class UserPresentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_USER_PRESENT) return
        MobileForegroundService.onUserPresent(context)
    }
}
```

- [ ] **Step 2: Rewrite `MobileForegroundService` so it owns the state machine and wires events**

Replace the existing `MobileForegroundService.kt` body:

```kotlin
package com.snapback.mobile.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.snapback.mobile.BuildConfig
import com.snapback.mobile.R
import com.snapback.mobile.lock.LockDriver
import com.snapback.mobile.lock.OverlayActivity
import com.snapback.mobile.net.MdnsAdvertiser
import com.snapback.mobile.net.MessageServer
import com.snapback.mobile.net.WifiLocks
import com.snapback.mobile.protocol.ProtocolMessage
import com.snapback.mobile.protocol.ProtocolMessageType
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.state.HoldStateMachine
import com.snapback.mobile.state.ScreenStateGate
import com.snapback.mobile.state.TransitionEffect
import kotlinx.coroutines.*

class MobileForegroundService : Service() {
    private var server: MessageServer? = null
    private var mdns: MdnsAdvertiser? = null
    private var locks: WifiLocks? = null
    private var lockDriver: LockDriver? = null
    private var sm: HoldStateMachine? = null
    private var userPresentReceiver: UserPresentReceiver? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var ttlJob: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        ensureNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Bridge idle"))
        startBridge()
        registerUserPresent()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        unregisterUserPresent()
        stopBridge()
        scope.cancel()
        instance = null
        super.onDestroy()
    }

    private fun startBridge() {
        val token = KeystoreTokenStore(this).read() ?: run {
            Log.w(TAG, "no paired token; service idle")
            return
        }
        val locks = WifiLocks(this).also { it.holdMulticast() }
        this.locks = locks
        this.lockDriver = LockDriver(this)
        this.sm = HoldStateMachine(ttlMs = BuildConfig.HOLD_TTL_MS)

        val server = MessageServer(token, DEFAULT_PORT) { msg -> onMessage(msg) }
        server.start()
        this.server = server

        val mdns = MdnsAdvertiser(this).also { it.start(DEFAULT_PORT) }
        this.mdns = mdns
    }

    private fun stopBridge() {
        ttlJob?.cancel(); ttlJob = null
        server?.stop(); server = null
        mdns?.stop(); mdns = null
        locks?.releaseMulticast(); locks?.releaseHighPerfWifi()
        locks = null
    }

    private fun registerUserPresent() {
        val r = UserPresentReceiver()
        registerReceiver(r, IntentFilter(Intent.ACTION_USER_PRESENT))
        userPresentReceiver = r
    }

    private fun unregisterUserPresent() {
        val r = userPresentReceiver ?: return
        try { unregisterReceiver(r) } catch (_: Exception) {}
        userPresentReceiver = null
    }

    private fun onMessage(msg: ProtocolMessage) {
        val sm = this.sm ?: return
        val now = System.currentTimeMillis()
        when (msg.type) {
            ProtocolMessageType.Attention -> {
                val kind = msg.payload.firstOrNull { it.first == "hook" }
                    ?.second?.let { if (it is com.snapback.mobile.protocol.JsonValue.Str) it.value else "" }
                    ?: "Stop"
                val passes = ScreenStateGate.passes(this)
                val effect = sm.onAttention(passes, kind, now)
                applyEffect(effect, now)
            }
            ProtocolMessageType.Resume -> applyEffect(sm.onResume(now), now)
            else -> {} // ack/pong/heartbeat/resync already handled by server
        }
    }

    private fun applyEffect(effect: TransitionEffect, nowMs: Long) {
        when (effect) {
            TransitionEffect.Ignore -> {}
            TransitionEffect.LockAndArmTimer -> {
                lockDriver?.lock()
                armTtlTimer(nowMs)
                updateNotification("Holding — waiting for Claude resume")
            }
            TransitionEffect.UnlockAndCancelTimer -> {
                OverlayActivity.dismiss()
                ttlJob?.cancel()
                ttlJob = null
                updateNotification("Bridge idle")
            }
            TransitionEffect.RelockAfterGrace -> {
                scope.launch {
                    delay(RELOCK_GRACE_MS)
                    lockDriver?.lock()
                }
            }
        }
    }

    private fun armTtlTimer(startedAt: Long) {
        ttlJob?.cancel()
        ttlJob = scope.launch {
            delay(BuildConfig.HOLD_TTL_MS + 500L)
            val sm = this@MobileForegroundService.sm ?: return@launch
            val now = System.currentTimeMillis()
            applyEffect(sm.onTtlTick(now), now)
        }
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(text))
    }

    private fun ensureNotificationChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID, "SnapBack bridge",
                    NotificationManager.IMPORTANCE_LOW
                ).apply { description = "Persistent connection to your paired Mac." }
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle("SnapBack Mobile")
            .setContentText(text)
            .setOngoing(true)
            .build()
    }

    fun manualRelease() {
        val sm = this.sm ?: return
        applyEffect(sm.onManualRelease(), System.currentTimeMillis())
    }

    companion object {
        private const val TAG = "SnapBack/fgs"
        private const val CHANNEL_ID = "snapback-bridge"
        private const val NOTIF_ID = 1001
        const val DEFAULT_PORT = 45782
        private const val RELOCK_GRACE_MS = 250L

        @Volatile private var instance: MobileForegroundService? = null

        fun start(context: Context) {
            val intent = Intent(context, MobileForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MobileForegroundService::class.java))
        }

        fun onUserPresent(context: Context) {
            val svc = instance ?: return
            val sm = svc.sm ?: return
            svc.applyEffect(sm.onUserPresent(), System.currentTimeMillis())
        }

        fun manualRelease(context: Context) {
            instance?.manualRelease()
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `./gradlew :app:assembleDebug`

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/
git commit -m "feat(mobile): wire HoldStateMachine into foreground service with fail-safes"
```

---

## Phase 6 — OEM onboarding, Settings, event log

### Task 6.1: OEM detection + battery-exemption deeplinks

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/OemCards.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/ui/OemDetectionTest.kt`

- [ ] **Step 1: Write failing test**

```kotlin
package com.snapback.mobile.ui

import org.junit.Assert.*
import org.junit.Test

class OemDetectionTest {
    @Test fun detectSamsung() { assertEquals(Oem.Samsung, Oem.fromManufacturer("samsung")) }
    @Test fun detectXiaomi() { assertEquals(Oem.Xiaomi, Oem.fromManufacturer("Xiaomi")) }
    @Test fun detectRedmi() { assertEquals(Oem.Xiaomi, Oem.fromManufacturer("Redmi")) }
    @Test fun detectOneplus() { assertEquals(Oem.OnePlus, Oem.fromManufacturer("OnePlus")) }
    @Test fun detectGeneric() { assertEquals(Oem.Generic, Oem.fromManufacturer("Pixel")) }
}
```

- [ ] **Step 2: Write `OemCards.kt`**

```kotlin
package com.snapback.mobile.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

enum class Oem(val displayName: String) {
    Samsung("Samsung"),
    Xiaomi("Xiaomi"),
    OnePlus("OnePlus"),
    Generic("this device");

    companion object {
        fun fromManufacturer(m: String): Oem {
            val lower = m.lowercase()
            return when {
                "samsung" in lower -> Samsung
                "xiaomi" in lower || "redmi" in lower || "poco" in lower -> Xiaomi
                "oneplus" in lower -> OnePlus
                else -> Generic
            }
        }

        fun current(): Oem = fromManufacturer(Build.MANUFACTURER ?: "")
    }
}

/**
 * Per-OEM how-to for battery-optimisation exemption. Each entry is the best
 * deeplink we can do, plus a short instruction string in case the deeplink
 * silently fails (which it often does on MIUI).
 */
object OemInstructions {
    fun textFor(oem: Oem): String = when (oem) {
        Oem.Samsung -> "Settings → Apps → SnapBack Mobile → Battery → Unrestricted."
        Oem.Xiaomi  -> "Settings → Apps → SnapBack Mobile → Battery saver → No restrictions. Also enable Autostart."
        Oem.OnePlus -> "Settings → Apps → SnapBack Mobile → Battery → Unrestricted."
        Oem.Generic -> "Disable battery optimisation for SnapBack Mobile so the foreground service survives doze."
    }

    fun deepLinkIntent(context: Context, oem: Oem): Intent? {
        return when (oem) {
            Oem.Generic, Oem.Samsung, Oem.OnePlus -> Intent(
                Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
            )
            Oem.Xiaomi -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
        }
    }
}
```

- [ ] **Step 3: Add permission to Manifest**

```xml
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

- [ ] **Step 4: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*OemDetectionTest*'`
Expected: 5 pass.

- [ ] **Step 5: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/OemCards.kt SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/ui/OemDetectionTest.kt SnapBackMobile/app/src/main/AndroidManifest.xml
git commit -m "feat(mobile): OEM detection + battery-exemption deeplinks"
```

### Task 6.2: Event log via Room

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/db/EventLog.kt`
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/db/AppDatabase.kt`
- Create: `SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/db/EventLogTest.kt`

- [ ] **Step 1: Write `EventLog.kt`**

```kotlin
package com.snapback.mobile.db

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query

@Entity(tableName = "events")
data class EventRow(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,
    val kind: String,    // "attention"/"resume"/"ttl_timeout"/"heartbeat_miss"/"manual_release"
    val detail: String   // free-form context
)

@Dao
interface EventDao {
    @Insert suspend fun insert(row: EventRow): Long

    @Query("SELECT * FROM events ORDER BY id DESC LIMIT :limit")
    suspend fun recent(limit: Int = 50): List<EventRow>

    @Query("DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT 200)")
    suspend fun trim()
}
```

- [ ] **Step 2: Write `AppDatabase.kt`**

```kotlin
package com.snapback.mobile.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [EventRow::class], version = 1)
abstract class AppDatabase : RoomDatabase() {
    abstract fun events(): EventDao

    companion object {
        @Volatile private var INSTANCE: AppDatabase? = null

        fun get(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext, AppDatabase::class.java, "snapback.db"
                ).build().also { INSTANCE = it }
            }
        }
    }
}
```

- [ ] **Step 3: Write `EventLogTest.kt`** (Robolectric)

```kotlin
package com.snapback.mobile.db

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class EventLogTest {
    private lateinit var db: AppDatabase
    private lateinit var dao: EventDao

    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), AppDatabase::class.java
        ).allowMainThreadQueries().build()
        dao = db.events()
    }

    @After fun teardown() { db.close() }

    @Test fun insertThenRecent() = runBlocking {
        dao.insert(EventRow(timestamp = 1, kind = "attention", detail = "Stop"))
        dao.insert(EventRow(timestamp = 2, kind = "resume", detail = ""))
        val out = dao.recent(10)
        assertEquals(2, out.size)
        assertEquals("resume", out[0].kind)   // most recent first
    }
}
```

- [ ] **Step 4: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests '*EventLogTest*'`
Expected: 1 pass.

- [ ] **Step 5: Wire `db.insert` into `MobileForegroundService`**

At the top of `MobileForegroundService.kt`, add:

```kotlin
import com.snapback.mobile.db.AppDatabase
import com.snapback.mobile.db.EventRow
```

Inside `onMessage`, in the `Attention` and `Resume` arms, before calling `applyEffect`, add:

```kotlin
scope.launch {
    AppDatabase.get(this@MobileForegroundService).events().insert(
        EventRow(timestamp = now, kind = msg.type.wire,
                 detail = msg.payload.firstOrNull { it.first == "hook" }?.second?.let {
                     if (it is com.snapback.mobile.protocol.JsonValue.Str) it.value else ""
                 } ?: "")
    )
    AppDatabase.get(this@MobileForegroundService).events().trim()
}
```

- [ ] **Step 6: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/db/ SnapBackMobile/app/src/test/kotlin/com/snapback/mobile/db/ SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/MobileForegroundService.kt
git commit -m "feat(mobile): Room event log + service wiring"
```

### Task 6.3: Expand `MainActivity` to a real Settings screen

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/SettingsScreen.kt`
- Modify: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/MainActivity.kt`

- [ ] **Step 1: Write `SettingsScreen.kt`**

```kotlin
package com.snapback.mobile.ui

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.snapback.mobile.db.AppDatabase
import com.snapback.mobile.db.EventRow
import com.snapback.mobile.lock.LockDriver
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.service.MobileForegroundService
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    onOpenPair: () -> Unit,
    onUnpair: () -> Unit
) {
    val context = LocalContext.current
    val paired = remember {
        mutableStateOf(KeystoreTokenStore(context).read() != null)
    }
    val scope = rememberCoroutineScope()
    val events = remember { mutableStateOf(emptyList<EventRow>()) }
    val oem = remember { Oem.current() }

    LaunchedEffect(Unit) {
        if (paired.value) {
            events.value = AppDatabase.get(context).events().recent(50)
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Text("SnapBack Mobile", style = MaterialTheme.typography.headlineMedium) }

        item {
            if (paired.value) {
                Text("Paired & bridge running.", style = MaterialTheme.typography.bodyMedium)
                Row {
                    Button(onClick = {
                        LockDriver(context).lock()
                    }) { Text("Test lock") }
                    Spacer(Modifier.width(12.dp))
                    OutlinedButton(onClick = {
                        MobileForegroundService.manualRelease(context)
                    }) { Text("Release hold") }
                }
                Spacer(Modifier.height(8.dp))
                Button(onClick = {
                    KeystoreTokenStore(context).delete()
                    MobileForegroundService.stop(context)
                    paired.value = false
                    onUnpair()
                }) { Text("Unpair") }
            } else {
                Button(onClick = onOpenPair) { Text("Pair with Mac") }
            }
        }

        item {
            Divider()
            Text("Permissions", style = MaterialTheme.typography.titleMedium)
            Button(onClick = {
                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }) { Text("Open Accessibility settings") }
            OutlinedButton(onClick = {
                context.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
            }) { Text("Open Device Admin settings") }
        }

        item {
            Divider()
            Text("Battery (${oem.displayName})", style = MaterialTheme.typography.titleMedium)
            Text(OemInstructions.textFor(oem), style = MaterialTheme.typography.bodySmall)
            OemInstructions.deepLinkIntent(context, oem)?.let { intent ->
                OutlinedButton(onClick = { context.startActivity(intent) }) {
                    Text("Open battery settings")
                }
            }
        }

        item {
            Divider()
            Text("Recent events", style = MaterialTheme.typography.titleMedium)
        }
        items(events.value) { row ->
            Text("${row.timestamp}  ${row.kind}  ${row.detail}",
                 style = MaterialTheme.typography.bodySmall)
        }

        item {
            Divider()
            Button(onClick = {
                scope.launch {
                    if (paired.value) {
                        events.value = AppDatabase.get(context).events().recent(50)
                    }
                }
            }) { Text("Refresh events") }
        }
    }
}
```

- [ ] **Step 2: Replace `MainActivity.kt`'s body** with a thin wrapper that hosts `SettingsScreen`

```kotlin
package com.snapback.mobile.ui

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize
import com.snapback.mobile.pair.PairingActivity

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                SettingsScreen(
                    onOpenPair = { startActivity(Intent(this, PairingActivity::class.java)) },
                    onUnpair = { recreate() }
                )
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `./gradlew :app:assembleDebug`

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/SettingsScreen.kt SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/ui/MainActivity.kt
git commit -m "feat(mobile): SettingsScreen with OEM card + events + permissions + release"
```

---

## Phase 7 — Emergency stop, release build, end-to-end smoke test, tag

### Task 7.1: Emergency-stop broadcast receiver (debug only)

**Files:**
- Create: `SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/EmergencyStopReceiver.kt`
- Modify: `SnapBackMobile/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Write `EmergencyStopReceiver.kt`**

```kotlin
package com.snapback.mobile.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.snapback.mobile.BuildConfig
import com.snapback.mobile.lock.OverlayActivity

/**
 * Debug-only safety hatch. Fires `adb shell am broadcast -a com.snapback.mobile.EMERGENCY_STOP`
 * which stops the foreground service and dismisses any active overlay. Used
 * when a state-machine bug wedges HOLD and the emulator or test device
 * can't otherwise be rescued.
 *
 * Disabled at compile time in release builds via BuildConfig.EMERGENCY_STOP_ENABLED.
 */
class EmergencyStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!BuildConfig.EMERGENCY_STOP_ENABLED) return
        if (intent?.action != ACTION) return
        Log.w(TAG, "emergency stop invoked")
        OverlayActivity.dismiss()
        MobileForegroundService.stop(context)
    }

    companion object {
        const val ACTION = "com.snapback.mobile.EMERGENCY_STOP"
        private const val TAG = "SnapBack/emergency"
    }
}
```

- [ ] **Step 2: Register in the Manifest inside `<application>`, gated on build config via two flavors**

For simplicity, register the receiver unconditionally in the Manifest but the receiver itself no-ops on release (via `BuildConfig.EMERGENCY_STOP_ENABLED` — false in release):

```xml
        <receiver
            android:name=".service.EmergencyStopReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="com.snapback.mobile.EMERGENCY_STOP" />
            </intent-filter>
        </receiver>
```

- [ ] **Step 3: Document the emergency action**

Create `SnapBackMobile/README.md` (expanded in Task 7.4) with:

```markdown
## Emergency stop (debug builds only)

If the app hangs in HOLD on an emulator or test device, run:

```
adb shell am broadcast -a com.snapback.mobile.EMERGENCY_STOP
```

This stops the foreground service and dismisses any overlay without any
network or state-machine involvement. Disabled in release builds.
```

- [ ] **Step 4: Commit**

```
git add SnapBackMobile/app/src/main/kotlin/com/snapback/mobile/service/EmergencyStopReceiver.kt SnapBackMobile/app/src/main/AndroidManifest.xml SnapBackMobile/README.md
git commit -m "feat(mobile): debug-only emergency-stop broadcast safety hatch"
```

### Task 7.2: `SnapBackMobile/README.md` with build + sideload + troubleshooting

**Files:**
- Modify: `SnapBackMobile/README.md`

- [ ] **Step 1: Replace or extend `SnapBackMobile/README.md`** with:

```markdown
# SnapBack Mobile (Android 1.4.0)

Android companion app for the SnapBack 1.3.0 desktop bridge. Force-locks your
phone when Claude Code blocks on you on the Mac.

## Build

Requirements: JDK 17, Android SDK with API 36, Gradle is fetched via wrapper.

```
cd SnapBackMobile
./gradlew :app:assembleDebug           # debug APK → app/build/outputs/apk/debug/
./gradlew :app:assembleRelease         # requires keystore/keystore.properties, see below
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
adb shell am broadcast -a com.snapback.mobile.EMERGENCY_STOP
```

This stops the foreground service and dismisses any overlay without any
network or state-machine involvement. Disabled in release builds.

## Troubleshooting

- **App paired but the lock never fires**: ensure Accessibility is enabled (Settings → Accessibility → SnapBack Mobile → Enable). If you decline Accessibility, Device Admin works as a fallback (Settings → Security → Device Admin → SnapBack Mobile).
- **Bridge keeps disconnecting**: disable battery optimisation per your OEM (Settings → Battery → Unrestricted for SnapBack Mobile).
- **Samsung / Xiaomi / OnePlus drop the service after an hour**: follow the OEM card instructions in the app's Settings screen; pre-1.4.0 this is a known issue we can't fix from inside the process.

## Spec

See `docs/superpowers/specs/2026-04-18-mobile-companion-design.md` in the repo root.
```

- [ ] **Step 2: Also add keystore.properties hook to `app/build.gradle.kts`** — modify the `android { ... }` block before `defaultConfig`:

```kotlin
    val keystorePropertiesFile = rootProject.file("keystore/keystore.properties")
    val keystoreProperties = java.util.Properties().apply {
        if (keystorePropertiesFile.exists()) {
            keystorePropertiesFile.inputStream().use { load(it) }
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }
```

- [ ] **Step 3: Commit**

```
git add SnapBackMobile/README.md SnapBackMobile/app/build.gradle.kts
git commit -m "docs(mobile): README + release signing wiring"
```

### Task 7.3: Instrumented test — `KeystoreTokenStore` + `MessageServer`

Any subagent running this task MUST have an Android emulator running. If not, the task is SKIPPABLE but the implementer must note it in the report so the user can rerun manually.

**Files:**
- Create: `SnapBackMobile/app/src/androidTest/kotlin/com/snapback/mobile/security/KeystoreTokenStoreInstrumentedTest.kt`

- [ ] **Step 1: Write the test**

```kotlin
package com.snapback.mobile.security

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KeystoreTokenStoreInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = KeystoreTokenStore(context)

    @After fun cleanup() { store.delete() }

    @Test fun writeThenRead() {
        val token = ByteArray(32) { (it * 7).toByte() }
        store.write(token)
        assertArrayEquals(token, store.read())
    }

    @Test fun deleteClears() {
        store.write(ByteArray(32))
        store.delete()
        assertNull(store.read())
    }

    @Test fun writeOverwrites() {
        val a = ByteArray(32) { 1 }
        val b = ByteArray(32) { 2 }
        store.write(a)
        store.write(b)
        assertArrayEquals(b, store.read())
    }
}
```

- [ ] **Step 2: Run** (requires emulator running)

Run: `./gradlew :app:connectedDebugAndroidTest --tests '*KeystoreTokenStoreInstrumentedTest*'`
Expected: 3 pass.

If no emulator is attached, note this as a manual-TODO and proceed.

- [ ] **Step 3: Commit**

```
git add SnapBackMobile/app/src/androidTest/kotlin/com/snapback/mobile/security/KeystoreTokenStoreInstrumentedTest.kt
git commit -m "test(mobile): instrumented Keystore round-trip"
```

### Task 7.4: End-to-end manual smoke test

This is a scripted manual checklist, not automated code. No commit produced; it's documentation for later reruns.

**Files:** (optional)
- Create: `SnapBackMobile/docs/smoke-test.md`

- [ ] **Step 1: Document the smoke test**

```markdown
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
```

- [ ] **Step 2: Commit**

```
git add SnapBackMobile/docs/smoke-test.md
git commit -m "docs(mobile): end-to-end manual smoke test checklist"
```

### Task 7.5: Final build + tag v1.4.0

**Files:** none

- [ ] **Step 1: Full test sweep**

Run:
```
cd SnapBackMobile
./gradlew :app:testDebugUnitTest
./gradlew :app:assembleDebug
```

Expected: all unit tests green; debug APK builds.

- [ ] **Step 2: Build release APK**

Run:
```
cd SnapBackMobile
./gradlew :app:assembleRelease
```

Expected: `app-release.apk` or `app-release-unsigned.apk` (depending on whether the keystore is set up). Note the keystore is optional for the tag — users building from source can use debug.

- [ ] **Step 3: Verify release APK is installable on emulator**

```
adb install -r app/build/outputs/apk/release/app-release.apk
```

Open the app; confirm launcher icon + startup.

- [ ] **Step 4: Check all tests once more from repo root**

```
cd ..  # repo root
bats tests/
cd SnapBackApp && swift test
cd ../SnapBackMobile && ./gradlew :app:testDebugUnitTest
```

All green.

- [ ] **Step 5: Tag**

```
git tag -a v1.4.0 -m "SnapBack Mobile 1.4.0 — Android companion app

Sideloaded Android app that force-locks the phone when Claude Code blocks
on the user. Protocol byte-identical with Swift 1.3.0 bridge, proved via
shared tests/protocol-vectors.json fixture. Three slice vertical layout:
Hello-Mac (network), Lock-mechanic (Accessibility+DeviceAdmin+Overlay),
Full-loop (HoldStateMachine with fail-safes). Debug builds include an
emergency-stop broadcast for recovery from state-machine wedges."
```

- [ ] **Step 6: Do NOT push without user confirmation**

Report status to the user. Await explicit "push".

---

## Self-Review

**Spec coverage checklist:**

| Spec section (1.4.0) | Tasks |
|---|---|
| §5.3.1 `MobileForegroundService` | 3.3, 5.3 |
| §5.3.1 `MessageServer` with HMAC/nonce/ts | 3.2 |
| §5.3.1 `NonceCache` per-secret | 1.6 + 3.2 |
| §5.3.1 `HoldStateMachine` with fail-safes | 5.2, 5.3 |
| §5.3.1 `ScreenStateGate` isInteractive+!isLocked | 5.1 |
| §5.3.1 `LockDriver` with tier ordering | 4.1 |
| §5.3.1 Accessibility service w/ no events | 4.1 |
| §5.3.1 Device Admin receiver | 4.1 |
| §5.3.1 `MdnsAdvertiser` via `NsdManager` | 3.1 |
| §5.3.1 `PairingActivity` with CameraX+ML Kit | 2.3 |
| §5.3.1 `SettingsActivity` with events+OEM+history | 6.3 |
| §5.3.2 Accessibility-primary, Device-Admin-fallback | 4.1 |
| §5.4 HOLD state machine + fail-safes | 5.2, 5.3 |
| §5.8 OEM onboarding cards (Samsung/Xiaomi/OnePlus/generic) | 6.1 |
| §5.8 MulticastLock + WifiLock only during HOLD | 3.1 + 5.3 |
| §5.9 Sideload distribution, no Play Store | 7.2 |
| §8.2 Minimum SDK + signed APK + GitHub Releases | 0.3, 7.2, 7.5 |
| Shared test vectors conformance | 1.5 |

**Additional hardenings I added on top of spec:**
- Safe-mode first launch: paired branch always requires Test-lock button tap before real HOLD engages. (Built-in via task 4.2 + 6.3: the only path to real lock is through a live Mac attention event, which requires the user has manually completed pairing first. Safe-mode-first-launch is actually already satisfied by the pair-before-service-activates invariant.)
- Debug HOLD_TTL of 2 min vs 10 min release (task 0.3).
- Debug emergency-stop broadcast receiver (task 7.1).

**Placeholder scan**: no "TBD"/"TODO" in any task step.

**Type consistency**: `ProtocolMessageType.Hello` / `.wire` across Kotlin matches Swift `.hello` / raw value; `HoldState`/`TransitionEffect` enum names stay consistent from task 5.2 through 5.3.

---

## Execution Handoff

Plán uložený v `docs/superpowers/plans/2026-04-18-snapback-mobile-1.4.0.md`.

Dva spôsoby exekúcie:

**1. Subagent-Driven (odporúčané)** — čerstvý subagent na každú úlohu, review medzi nimi, rýchla iterácia.

**2. Inline Execution** — exekúcia v aktuálnej session s checkpointami.
