# SnapBack Unification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify SnapBack's CLI and SwiftUI menu-bar app around a single authoritative config writer, fix known destructive bugs, and ship 1.2.0.

**Architecture:** A new `snapback-lib.sh` shell library owns `config_set`/`config_get` (awk-style read-loop writer + `flock`). The CLI gains generic `config get/set/show/path` subcommands plus typed wrappers (`volume`, `browser`, `focus`, `test`, and a refactored `mode`). The menu-bar app reads the config directly (with a `DispatchSource` watcher + echo suppression) but performs *all* mutations by fork-execing the CLI. Distribution: `install.sh` optionally builds `SnapBackApp` via Swift and copies `SnapBack.app` to `/Applications`; `snapback update` keeps it in sync.

**Tech stack:**
- Bash 3.2 (macOS system bash)
- `jq` (already required)
- `awk`, `flock`, `osascript`, `afplay`
- Swift 5.9+, SwiftUI / Combine / ServiceManagement (menu-bar app, macOS 13+)
- [bats-core](https://github.com/bats-core/bats-core) for shell tests (`brew install bats-core` on the dev machine; not a user-facing dep)

**Spec:** `docs/superpowers/specs/2026-04-18-snapback-unification-design.md` (read first; tasks reference sections like §4.1).

---

## File map

**Create:**
- `snapback-lib.sh` — the config API (`config_set`, `config_get`, validators, known-keys table, flock helper).
- `tests/config_set.bats` — bats tests for `config_set` / `config_get`.
- `tests/cli_typed.bats` — bats tests for typed wrappers.
- `SnapBackApp/Sources/SnapBackApp/Services/SnapBackCLI.swift` — binary resolution + typed invocation helpers.
- `SnapBackApp/Sources/SnapBackApp/Services/ConfigWatcher.swift` — file watcher with echo-suppression window.

**Modify:**
- `.gitignore` — exclude build artifacts.
- `snapback` (CLI) — source the lib; new `config`/`volume`/`browser`/`focus`/`test` subcommands; refactor `cmd_mode`; fix `cmd_update` tarball branch; extend `cmd_uninstall` and `cmd_status`; bump VERSION.
- `snapback.sh` — extract `_play_notification` helper (dedupe three call sites); no behavior change.
- `install.sh` — source the lib; use `config_set` for writes; migration for missing keys; preserving `jq` in `setup_hooks`; quiet permissions probe; menu-bar build prompt.
- `SnapBackApp/Sources/SnapBackApp/Models/AppState.swift` — remove `saveConfig`, add per-key setters, extend `loadConfig`, harden parser.
- `SnapBackApp/Sources/SnapBackApp/Utilities/ShellCommand.swift` — `run(executable:args:)` with exit code + PATH augmentation.
- `SnapBackApp/Sources/SnapBackApp/Views/MenuBarView.swift` — error banner; re-enable controls in F3; effective-volume readout.
- `SnapBackApp/Sources/SnapBackApp/Views/FocusAppsView.swift` — chevron reorder.
- `SnapBackApp/build-app.sh` — emit `SnapBackCLIPath` in `Info.plist`.
- `README.md` — menu-bar + new commands.
- `ROADMAP.md` — tick menu-bar item.

**Do not modify in this plan:**
- `snapback-resume.sh` (already pure-read, no changes needed).
- `get.sh` (already clones/tarballs the whole repo; new files ride along).
- `notification.mp3`, `LICENSE`, `RESEARCH.md`, `CLAUDE.md`.

---

## Phase F0a — Repo hygiene + checkpoint CLI changes

### Task F0a.1: Update `.gitignore` and commit both the ignore rules and the currently uncommitted CLI changes

**Files:**
- Modify: `.gitignore`
- Commit (staged from current working tree): `config.example`, `snapback`, `snapback.sh`

- [ ] **Step 1: Replace the current `.gitignore` with the expanded rules**

Current content is just `.DS_Store`. Overwrite:

```gitignore
# macOS
.DS_Store

# Swift build artifacts
SnapBackApp/.build/
SnapBackApp/SnapBack.app/
```

Use the Write tool (or `cat >`) to set exactly this content.

- [ ] **Step 2: Unstage any already-tracked build artifacts**

Run:
```bash
git ls-files SnapBackApp/.build/ SnapBackApp/SnapBack.app/ 2>/dev/null | xargs -I{} git rm --cached {} 2>/dev/null; true
```
Expected: no output (these are currently untracked, so nothing to remove). If output appears, it was tracked — the command now removes it from the index.

- [ ] **Step 3: Verify working tree**

Run: `git status`
Expected: `.gitignore` modified, plus pre-existing modifications to `config.example`, `snapback`, `snapback.sh`, and untracked `SnapBackApp/`.

- [ ] **Step 4: Stage `.gitignore`, commit hygiene**

```bash
git add .gitignore
git commit -m "chore: ignore Swift build artifacts"
```

- [ ] **Step 5: Stage and commit the existing VOLUME / fast-path / `app` command changes**

```bash
git add config.example snapback snapback.sh
git commit -m "$(cat <<'EOF'
feat: add VOLUME config, sound-mode fast path, and `app` subcommand

Carries the previously uncommitted changes into history so the
upcoming refactor has a clean base. Behavior unchanged.
EOF
)"
```

- [ ] **Step 6: Sanity check**

Run: `git log --oneline -3 && git status`
Expected: two new commits; `git status` shows only untracked `SnapBackApp/`.

---

## Phase F0b — Menu-bar sources with defanged `saveConfig`

### Task F0b.1: Stub `saveConfig`, disable mutating UI, and commit the menu-bar sources

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Models/AppState.swift`
- Modify: `SnapBackApp/Sources/SnapBackApp/Views/MenuBarView.swift`
- Modify: `SnapBackApp/Sources/SnapBackApp/Views/FocusAppsView.swift`
- Commit: the whole `SnapBackApp/` directory (sources + `Package.swift` + `build-app.sh`)

- [ ] **Step 1: Stub `AppState.saveConfig()`**

In `SnapBackApp/Sources/SnapBackApp/Models/AppState.swift`, replace the body of `saveConfig()` (the method starting around line 93) with a guarded no-op that logs:

```swift
func saveConfig() {
    // F0b: writer is a no-op until F3 wires mutations through the CLI.
    // Kept callable so callsites compile; the UI controls that would
    // drive it are .disabled(true) at the view layer.
    NSLog("SnapBack: saveConfig() is a no-op until F3")
}
```

Leave the rest of `AppState` (loadConfig, parsers, toggleEnabled, etc.) untouched.

- [ ] **Step 2: Disable mutating controls in `MenuBarView`**

In `SnapBackApp/Sources/SnapBackApp/Views/MenuBarView.swift`, add `.disabled(true)` to:
- the volume `Slider(...)` (inside `volumeSection`)
- the "play test sound" `Button` (inside `volumeSection`)
- the mode `Picker(...)` (inside `modeSection`)
- the browser `Picker(...)`, throttle `Stepper`, seek-back `Stepper` (inside `settingsSection`)

Leave the on/off `Toggle` in `headerSection` enabled — it goes through `snapback on`/`off`, which already works via shell-out.

Leave "Start at Login" and "Quit" enabled.

- [ ] **Step 3: Disable mutating controls in `FocusAppsView`**

In `SnapBackApp/Sources/SnapBackApp/Views/FocusAppsView.swift`, add `.disabled(true)` to the "Add" button and the remove button inside `AppChip`.

- [ ] **Step 4: Build the app to verify it still compiles**

```bash
cd SnapBackApp && swift build -c release && cd ..
```
Expected: build succeeds (warnings OK, errors not).

- [ ] **Step 5: Stage the SwiftUI sources and commit**

```bash
git add SnapBackApp/Package.swift SnapBackApp/build-app.sh SnapBackApp/Sources
git commit -m "$(cat <<'EOF'
feat: add SwiftUI menu-bar app (read-only pending F3)

Commits sources for the menu-bar front-end. saveConfig is a no-op
and mutating controls are disabled; writes land in F3 once the CLI
is the single writer. Build artifacts (.build, SnapBack.app) are
ignored per .gitignore.
EOF
)"
```

- [ ] **Step 6: Confirm `git status` is clean**

Run: `git status`
Expected: `nothing to commit, working tree clean`.

---

## Phase F1 — `snapback-lib.sh` + `config_set` foundation

### Task F1.1: Bats scaffolding and first failing test

**Files:**
- Create: `tests/config_set.bats`
- Create: `snapback-lib.sh` (skeleton)

- [ ] **Step 1: Verify bats is installed**

Run: `bats --version`
Expected: `Bats 1.x.x`. If missing: `brew install bats-core`.

- [ ] **Step 2: Create the empty lib skeleton**

Create `snapback-lib.sh` with:

```bash
#!/bin/bash
# snapback-lib.sh - shared config API for the SnapBack CLI and installer.
# Sourced; do not execute directly.

# Source-once guard
[[ -n "${SNAPBACK_LIB_LOADED:-}" ]] && return 0
SNAPBACK_LIB_LOADED=1

# Config file path (overridable for tests)
: "${SNAPBACK_CONFIG_FILE:=${XDG_CONFIG_HOME:-$HOME/.config}/snapback/config}"
```

Do **not** `chmod +x` — it's sourced, not executed.

- [ ] **Step 3: Write the first failing test**

Create `tests/config_set.bats`:

```bash
#!/usr/bin/env bats
# Tests for snapback-lib.sh config_set / config_get

setup() {
  TMP="$(mktemp -d -t snapback-test.XXXXXX)"
  export SNAPBACK_CONFIG_FILE="$TMP/config"
  : > "$SNAPBACK_CONFIG_FILE"
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../snapback-lib.sh"
}

teardown() {
  rm -rf "$TMP"
}

@test "config_set appends a new scalar key quoted" {
  config_set MODE sound --allow-new
  run cat "$SNAPBACK_CONFIG_FILE"
  [ "$status" -eq 0 ]
  grep -qx 'MODE="sound"' "$SNAPBACK_CONFIG_FILE"
}
```

- [ ] **Step 4: Run the test and confirm it fails**

Run: `bats tests/config_set.bats`
Expected: FAIL — `config_set: command not found` (function doesn't exist yet).

### Task F1.2: Implement minimal `config_set` (append path)

**Files:**
- Modify: `snapback-lib.sh`

- [ ] **Step 1: Add the known-keys table and escaping helper**

Append to `snapback-lib.sh`:

```bash
# Known keys table.  Values are type tags: "scalar" or "array".
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
EOF
}

_snapback_key_type() {
  local key="$1"
  _snapback_known_keys | awk -v k="$key" '$1 == k { print $2; found=1 } END { exit found ? 0 : 1 }'
}

# Escape a value for writing inside double-quotes in a bash-sourced file.
# Escapes: backslash, dollar, backtick, double-quote.
_snapback_escape_value() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\$/\\\$}"
  v="${v//\`/\\\`}"
  v="${v//\"/\\\"}"
  printf '%s' "$v"
}
```

- [ ] **Step 2: Add minimal `config_set` supporting the "append scalar" path**

Append:

```bash
# Usage: config_set KEY VALUE [--allow-new]
config_set() {
  local key="$1" value="$2" allow_new=0
  shift 2 || return 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --allow-new) allow_new=1 ;;
      *) echo "config_set: unknown flag: $1" >&2; return 2 ;;
    esac
    shift
  done

  # Validate: key is known, or --allow-new was passed
  local ktype
  if ktype=$(_snapback_key_type "$key"); then
    :
  else
    if (( allow_new == 0 )); then
      echo "config_set: unknown key: $key" >&2
      return 2
    fi
    ktype="scalar"
  fi

  # Validate: no newlines or NULs in value
  if [[ "$value" == *$'\n'* ]]; then
    echo "config_set: value contains newline" >&2
    return 2
  fi

  # Ensure parent dir and file exist
  mkdir -p "$(dirname "$SNAPBACK_CONFIG_FILE")"
  [[ -f "$SNAPBACK_CONFIG_FILE" ]] || : > "$SNAPBACK_CONFIG_FILE"

  if [[ "$ktype" == "scalar" ]]; then
    local escaped
    escaped="$(_snapback_escape_value "$value")"
    # Does the key already exist?
    if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
      # Replace path lands in F1.3.
      echo "config_set: replace path not yet implemented" >&2
      return 3
    else
      printf '\n# Added by snapback config set\n%s="%s"\n' "$key" "$escaped" >> "$SNAPBACK_CONFIG_FILE"
    fi
  else
    echo "config_set: array path not yet implemented" >&2
    return 3
  fi
}
```

- [ ] **Step 3: Run the test — expect PASS**

Run: `bats tests/config_set.bats`
Expected: 1 test passes.

- [ ] **Step 4: Commit**

```bash
git add snapback-lib.sh tests/config_set.bats
git commit -m "feat: add snapback-lib.sh with scalar-append config_set"
```

### Task F1.3: Replace-in-place for existing scalar keys, plus escape round-trip tests

**Files:**
- Modify: `snapback-lib.sh`
- Modify: `tests/config_set.bats`

- [ ] **Step 1: Add failing tests for the replace path and escaping**

Append to `tests/config_set.bats`:

```bash
@test "config_set replaces an existing scalar key in place" {
  printf 'MODE="full"\n# keep me\nVOLUME="0.5"\n' > "$SNAPBACK_CONFIG_FILE"
  config_set MODE sound
  grep -qx 'MODE="sound"' "$SNAPBACK_CONFIG_FILE"
  grep -qx '# keep me' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'VOLUME="0.5"' "$SNAPBACK_CONFIG_FILE"
}

@test "config_set escapes backslash, dollar, backtick, double-quote" {
  config_set NOTIFICATION_SOUND '/path/with $var `cmd` "q" \back'
  # Sourcing the file must produce the original value
  (
    # shellcheck disable=SC1090
    source "$SNAPBACK_CONFIG_FILE"
    [ "$NOTIFICATION_SOUND" = '/path/with $var `cmd` "q" \back' ]
  )
}

@test "config_set preserves unknown keys and comments" {
  printf '# top comment\nCUSTOM="keep"\nMODE="full"\n' > "$SNAPBACK_CONFIG_FILE"
  config_set MODE sound
  grep -qx '# top comment' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'CUSTOM="keep"' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'MODE="sound"' "$SNAPBACK_CONFIG_FILE"
}
```

Run: `bats tests/config_set.bats`
Expected: 3 new tests FAIL (replace path returns error 3; escape test probably fails too).

- [ ] **Step 2: Implement the replace path using a bash read-loop**

In `snapback-lib.sh`, replace the `config_set` scalar branch with:

```bash
  if [[ "$ktype" == "scalar" ]]; then
    local escaped new_line
    escaped="$(_snapback_escape_value "$value")"
    new_line="${key}=\"${escaped}\""

    if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
      _snapback_rewrite_scalar "$key" "$new_line"
    else
      printf '\n# Added by snapback config set\n%s\n' "$new_line" >> "$SNAPBACK_CONFIG_FILE"
    fi
    return 0
  fi
```

Add the helper above `config_set`:

```bash
# Rewrite the line that begins with KEY= to be exactly NEW_LINE.
# Reads the file line-by-line in bash (no sed — sed metachars in
# NEW_LINE would break substitution).
_snapback_rewrite_scalar() {
  local key="$1" new_line="$2"
  local tmp
  tmp="$(mktemp "${SNAPBACK_CONFIG_FILE}.tmp.XXXXXX")"
  local line replaced=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( replaced == 0 )) && [[ "$line" == "${key}="* ]]; then
      printf '%s\n' "$new_line" >> "$tmp"
      replaced=1
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$SNAPBACK_CONFIG_FILE"
  mv "$tmp" "$SNAPBACK_CONFIG_FILE"
}
```

- [ ] **Step 3: Run the tests**

Run: `bats tests/config_set.bats`
Expected: all 4 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add snapback-lib.sh tests/config_set.bats
git commit -m "feat(config_set): replace-in-place + escape round-trip"
```

### Task F1.4: `FOCUS_APPS` array write + `flock`-based concurrency

**Files:**
- Modify: `snapback-lib.sh`
- Modify: `tests/config_set.bats`

- [ ] **Step 1: Add failing tests for the array path and flock**

Append to `tests/config_set.bats`:

```bash
@test "config_set writes FOCUS_APPS as a bash array literal" {
  printf 'FOCUS_APPS=("Old")\nMODE="full"\n' > "$SNAPBACK_CONFIG_FILE"
  # Caller passes pre-formatted literal
  config_set FOCUS_APPS '("Cursor" "Ghostty")'
  grep -qx 'FOCUS_APPS=("Cursor" "Ghostty")' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'MODE="full"' "$SNAPBACK_CONFIG_FILE"
}

@test "config_set serializes concurrent writers via flock" {
  : > "$SNAPBACK_CONFIG_FILE"
  (config_set MODE sound --allow-new) &
  (config_set VOLUME "0.5" --allow-new) &
  wait
  # Both keys must be present
  grep -qx 'MODE="sound"' "$SNAPBACK_CONFIG_FILE"
  grep -qx 'VOLUME="0.5"' "$SNAPBACK_CONFIG_FILE"
}
```

Run: `bats tests/config_set.bats`
Expected: 2 new tests FAIL.

- [ ] **Step 2: Add array handling**

In `snapback-lib.sh`, replace the `else` branch (array) inside `config_set` with:

```bash
  if [[ "$ktype" == "array" ]]; then
    # Value must be a parenthesized bash-array literal.
    if [[ ! "$value" =~ ^\(.*\)$ ]]; then
      echo "config_set: array value must be (\"a\" \"b\" ...)" >&2
      return 2
    fi
    local new_line="${key}=${value}"
    if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
      _snapback_rewrite_scalar "$key" "$new_line"
    else
      printf '\n# Added by snapback config set\n%s\n' "$new_line" >> "$SNAPBACK_CONFIG_FILE"
    fi
    return 0
  fi
```

- [ ] **Step 3: Add flock wrapper**

Wrap the mutating portion of `config_set` with `flock`. Refactor `config_set` so validation happens first, then the locked region runs. Simplest: wrap the `if [[ ... scalar ]] ... else array ... fi` block.

Replace the mutating block with:

```bash
  local lockfile="${SNAPBACK_CONFIG_FILE}.lock"
  # Open fd 9 on the lockfile; flock -x on that fd
  (
    exec 9> "$lockfile"
    flock -x 9
    if [[ "$ktype" == "scalar" ]]; then
      local escaped new_line
      escaped="$(_snapback_escape_value "$value")"
      new_line="${key}=\"${escaped}\""
      if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
        _snapback_rewrite_scalar "$key" "$new_line"
      else
        printf '\n# Added by snapback config set\n%s\n' "$new_line" >> "$SNAPBACK_CONFIG_FILE"
      fi
    else
      if [[ ! "$value" =~ ^\(.*\)$ ]]; then
        echo "config_set: array value must be (\"a\" \"b\" ...)" >&2
        exit 2
      fi
      local new_line="${key}=${value}"
      if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
        _snapback_rewrite_scalar "$key" "$new_line"
      else
        printf '\n# Added by snapback config set\n%s\n' "$new_line" >> "$SNAPBACK_CONFIG_FILE"
      fi
    fi
  )
```

Note the subshell + `exec 9>` pattern means the fd closes (releasing the lock) when the subshell exits.

Verify `flock` is available:
```bash
command -v flock || echo "flock missing"
```
macOS ships `flock` in base 10.14+; if the host is older we'd need a Perl fallback — documented as a platform requirement.

- [ ] **Step 4: Run the tests**

Run: `bats tests/config_set.bats`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add snapback-lib.sh tests/config_set.bats
git commit -m "feat(config_set): FOCUS_APPS array writer + flock"
```

### Task F1.5: `config_get` and value-validation tests

**Files:**
- Modify: `snapback-lib.sh`
- Modify: `tests/config_set.bats`

- [ ] **Step 1: Add failing tests for `config_get` and rejected values**

Append to `tests/config_set.bats`:

```bash
@test "config_get returns a scalar value unquoted" {
  printf 'MODE="sound"\n' > "$SNAPBACK_CONFIG_FILE"
  run config_get MODE
  [ "$status" -eq 0 ]
  [ "$output" = "sound" ]
}

@test "config_get returns empty for absent key with status 1" {
  : > "$SNAPBACK_CONFIG_FILE"
  run config_get MODE
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "config_set rejects unknown key without --allow-new" {
  run config_set FROB bar
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown key"* ]]
}

@test "config_set rejects newline in value" {
  run config_set MODE $'line1\nline2'
  [ "$status" -ne 0 ]
  [[ "$output" == *"newline"* ]]
}
```

Run: `bats tests/config_set.bats`
Expected: 4 new tests FAIL (config_get undefined; unknown/newline tests may already partly pass depending on earlier impl — verify.)

- [ ] **Step 2: Implement `config_get`**

Append to `snapback-lib.sh`:

```bash
# Usage: config_get KEY
# Prints the value (unquoted) and returns 0 if the key is set; prints
# nothing and returns 1 if the key is absent.
config_get() {
  local key="$1"
  [[ -f "$SNAPBACK_CONFIG_FILE" ]] || return 1
  # Source in a subshell to avoid polluting caller env
  local value
  value=$(
    # shellcheck disable=SC1090
    source "$SNAPBACK_CONFIG_FILE" 2>/dev/null
    local -n ref="$key" 2>/dev/null || true
    if [[ "$(declare -p "$key" 2>/dev/null)" =~ declare\ -a ]]; then
      # Array — print space-quoted tokens
      eval "printf '%s ' \"\${${key}[@]}\""
    else
      printf '%s' "${!key-}"
    fi
  )
  if [[ -z "${value}" ]]; then
    # Distinguish "unset" from "empty string"
    if grep -q "^${key}=" "$SNAPBACK_CONFIG_FILE"; then
      printf '%s' ""
      return 0
    fi
    return 1
  fi
  printf '%s\n' "$value"
}
```

Note: bash 3.2 (macOS default) does not support `local -n` nameref. Replace with indirect expansion:

```bash
config_get() {
  local key="$1"
  [[ -f "$SNAPBACK_CONFIG_FILE" ]] || return 1
  local found
  found=$(grep -c "^${key}=" "$SNAPBACK_CONFIG_FILE" || true)
  [[ "$found" -gt 0 ]] || return 1
  (
    # shellcheck disable=SC1090
    source "$SNAPBACK_CONFIG_FILE" 2>/dev/null
    if declare -p "$key" 2>/dev/null | grep -q 'declare -a'; then
      eval "printf '%s\n' \"\${${key}[*]}\""
    else
      eval "printf '%s\n' \"\${${key}-}\""
    fi
  )
}
```

- [ ] **Step 3: Run tests**

Run: `bats tests/config_set.bats`
Expected: all 10 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add snapback-lib.sh tests/config_set.bats
git commit -m "feat(snapback-lib): config_get + stricter validation"
```

### Task F1.6: Wire the lib into the `snapback` CLI (`config` subcommand + `cmd_mode` refactor)

**Files:**
- Modify: `snapback`

- [ ] **Step 1: Source the lib at the top of `snapback`**

After the existing `SCRIPT_DIR=...` resolution block (around line 13 in `snapback`), insert:

```bash
# Load shared config library.  Priority: repo-adjacent, then system share path.
if [[ -f "$SCRIPT_DIR/snapback-lib.sh" ]]; then
  # shellcheck source=snapback-lib.sh
  source "$SCRIPT_DIR/snapback-lib.sh"
elif [[ -f "/usr/local/share/snapback/snapback-lib.sh" ]]; then
  source "/usr/local/share/snapback/snapback-lib.sh"
else
  echo "error: snapback-lib.sh not found" >&2
  exit 1
fi

# Align lib's config path with the CLI's.
SNAPBACK_CONFIG_FILE="$CONFIG_FILE"
```

- [ ] **Step 2: Add `cmd_config` function**

Before `cmd_install`, add:

```bash
# ============================================================
# CONFIG COMMAND
# ============================================================
cmd_config() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    get)
      [[ $# -ge 1 ]] || { print_error "Usage: snapback config get KEY"; exit 2; }
      config_get "$1" || { print_error "Key not set: $1"; exit 1; }
      ;;
    set)
      [[ $# -ge 2 ]] || { print_error "Usage: snapback config set KEY VALUE [--allow-new]"; exit 2; }
      config_set "$@" || exit $?
      ;;
    show)
      local json=0
      [[ "${1:-}" == "--json" ]] && json=1
      if (( json )); then
        local first=1
        echo "{"
        while read -r k _; do
          local v
          if v=$(config_get "$k" 2>/dev/null); then
            (( first )) || echo ","
            first=0
            # Shell-escape for JSON: minimal (no \n in values)
            local esc="${v//\\/\\\\}"
            esc="${esc//\"/\\\"}"
            printf '  "%s": "%s"' "$k" "$esc"
          fi
        done < <(_snapback_known_keys)
        echo ""
        echo "}"
      else
        while read -r k _; do
          local v
          if v=$(config_get "$k" 2>/dev/null); then
            printf '%s=%s\n' "$k" "$v"
          fi
        done < <(_snapback_known_keys)
      fi
      ;;
    path)
      printf '%s\n' "$CONFIG_FILE"
      ;;
    "")
      print_error "Usage: snapback config <get|set|show|path> ..."
      exit 2
      ;;
    *)
      print_error "Unknown config subcommand: $sub"
      exit 2
      ;;
  esac
}
```

- [ ] **Step 3: Refactor `cmd_mode` to delegate**

Replace the body of `cmd_mode` (starting around line 219) that does the `sed` replacement with a call to `config_set`. Keep the existing validation and output.

```bash
cmd_mode() {
  local mode="${1:-}"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Config not found. Run 'snapback install' first."
    exit 1
  fi
  if [[ -z "$mode" ]]; then
    source "$CONFIG_FILE"
    local current_mode="${MODE:-full}"
    echo ""
    echo "Current mode: $current_mode"
    if [[ "$current_mode" == "sound" ]]; then
      print_info "Sound only - no app switching"
    else
      print_info "Full mode - sound + app switching"
    fi
    echo ""
    echo "Change with: snapback mode <full|sound>"
    echo ""
    exit 0
  fi
  if [[ "$mode" != "full" && "$mode" != "sound" ]]; then
    print_error "Invalid mode: $mode"
    print_info "Valid modes: full, sound"
    exit 1
  fi
  config_set MODE "$mode" --allow-new || {
    print_error "Failed to write config"
    exit 1
  }
  print_success "Mode set to: $mode"
  if [[ "$mode" == "sound" ]]; then
    print_info "Sound only - no app switching"
  else
    print_info "Full mode - sound + app switching"
  fi
}
```

- [ ] **Step 4: Add `config` to the main dispatcher**

In `main()` (around line 432), add a case:

```bash
    config)
      cmd_config "$@"
      ;;
```

- [ ] **Step 5: Update help text**

In `show_help()`, add under Commands:

```
  config <sub>  Get/set config: get KEY | set KEY VAL | show [--json] | path
```

- [ ] **Step 6: Manual smoke test**

```bash
./snapback config path
./snapback config show
./snapback config set MODE full
./snapback config get MODE
./snapback config show --json
```
Expected: each prints sensible output; `get` after `set` echoes `full`.

- [ ] **Step 7: Commit**

```bash
git add snapback
git commit -m "feat(cli): config get/set/show/path; cmd_mode delegates to config_set"
```

### Task F1.7: `install.sh` uses `config_set`, migrates missing keys, preserving hooks, quiet probe

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Source the lib**

Near the top of `install.sh` (after `SCRIPT_DIR` resolution), insert:

```bash
# Load shared config library
if [[ -f "$SCRIPT_DIR/snapback-lib.sh" ]]; then
  source "$SCRIPT_DIR/snapback-lib.sh"
else
  echo "error: snapback-lib.sh not found next to install.sh" >&2
  exit 1
fi
SNAPBACK_CONFIG_FILE="$CONFIG_DIR/config"
```

- [ ] **Step 2: Replace the heredoc writer with `config_set` calls**

Find the block that writes the fresh config (the `cat > "$CONFIG_DIR/config" <<EOF` around line 120) and replace it with:

```bash
  mkdir -p "$CONFIG_DIR"
  : > "$CONFIG_DIR/config"

  # Build FOCUS_APPS bash-array literal
  focus_apps_literal='('
  for app in "${FOCUS_APPS_ARR[@]}"; do
    app="$(echo "$app" | xargs)"  # trim
    # Escape the same way config_set does (backslash, dollar, backtick, dquote)
    local_esc="${app//\\/\\\\}"
    local_esc="${local_esc//\$/\\\$}"
    local_esc="${local_esc//\`/\\\`}"
    local_esc="${local_esc//\"/\\\"}"
    focus_apps_literal+="\"$local_esc\" "
  done
  focus_apps_literal="${focus_apps_literal% })"

  config_set FOCUS_APPS "$focus_apps_literal" --allow-new
  config_set FOCUS_DELAY "$focus_delay" --allow-new
  config_set BROWSER "$browser" --allow-new
  config_set SEEK_BACK_SECONDS "$seek_back" --allow-new
  config_set THROTTLE_SECONDS "$throttle" --allow-new
  config_set NOTIFICATION_SOUND "$notification_sound" --allow-new
  config_set VOLUME "1.0" --allow-new
  config_set MODE "full" --allow-new
```

- [ ] **Step 3: Add a migration step when an existing config is kept**

Inside the `if [[ "$skip_config" == "true" ]]` branch (i.e., user chose to keep the current config), add:

```bash
  # Migrate: ensure all known keys exist with sensible defaults.
  config_get VOLUME >/dev/null || config_set VOLUME "1.0" --allow-new
  config_get MODE >/dev/null || config_set MODE "full" --allow-new
  # Other keys are written by fresh installs; nothing to backfill here
  # unless a future schema version adds more.
```

- [ ] **Step 4: Rewrite `setup_hooks` to preserve existing hooks**

Replace the `jq` expression inside `setup_hooks` with the same preserving filter used by `cmd_on`:

```bash
setup_hooks() {
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

  if ! command -v jq &>/dev/null; then
    print_warning "jq not found - please install with: brew install jq"
    print_info "Then run: snapback on"
    return 1
  fi

  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo '{}' > "$CLAUDE_SETTINGS"
  fi

  tmp=$(mktemp)
  jq --arg snapback "$SCRIPT_DIR/snapback.sh" --arg resume "$SCRIPT_DIR/snapback-resume.sh" '
    .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) | map(select(.hooks[0].command | contains("snapback") | not))) + [{"matcher": "*", "hooks": [{"type": "command", "command": $snapback}]}] |
    .hooks.Stop = ((.hooks.Stop // []) | map(select(.hooks[0].command | contains("snapback") | not))) + [{"hooks": [{"type": "command", "command": $snapback}]}] |
    .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(.hooks[0].command | contains("snapback") | not))) + [{"matcher": "Edit|Write|Bash", "hooks": [{"type": "command", "command": $resume}]}] |
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select(.hooks[0].command | contains("snapback") | not))) + [{"hooks": [{"type": "command", "command": $resume}]}]
  ' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
  return 0
}
```

- [ ] **Step 5: Replace end-of-installer permission probe with a quiet one**

Find the block that runs `"$SCRIPT_DIR/snapback.sh"` for permissions (around line 194). Replace with:

```bash
echo ""
print_info "Testing macOS permissions..."

# Quiet probe: just try System Events access. No app focus, no sound, no state.
if osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' &>/dev/null; then
  print_success "Permissions OK"
else
  print_warning "Grant permission: System Settings → Privacy & Security → Automation → Terminal/iTerm → System Events"
fi
```

- [ ] **Step 6: Manual smoke test**

```bash
# Backup real config to avoid clobbering the dev box
mv ~/.config/snapback/config ~/.config/snapback/config.backup 2>/dev/null || true
./install.sh -y
cat ~/.config/snapback/config
# Must contain FOCUS_APPS=(...), FOCUS_DELAY="0.5", ..., MODE="full", VOLUME="1.0"
# Restore
mv ~/.config/snapback/config.backup ~/.config/snapback/config 2>/dev/null || true
```

- [ ] **Step 7: Commit**

```bash
git add install.sh
git commit -m "feat(install): use config_set, preserve hooks, quiet permission probe"
```

---

## Phase F2 — Typed CLI wrappers

### Task F2.1: `snapback volume` and `snapback browser`

**Files:**
- Modify: `snapback`
- Create: `tests/cli_typed.bats`

- [ ] **Step 1: Write failing tests**

Create `tests/cli_typed.bats`:

```bash
#!/usr/bin/env bats
# Integration tests for typed CLI wrappers

setup() {
  TMP="$(mktemp -d -t snapback-cli.XXXXXX)"
  export SNAPBACK_CONFIG_FILE="$TMP/config"
  export XDG_CONFIG_HOME="$TMP"
  mkdir -p "$TMP/snapback"
  mv "$TMP/config" "$TMP/snapback/config" 2>/dev/null || true
  export SNAPBACK_CONFIG_FILE="$TMP/snapback/config"
  : > "$SNAPBACK_CONFIG_FILE"
  # Seed known keys so --allow-new isn't needed
  "$BATS_TEST_DIRNAME/../snapback" config set MODE full --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set VOLUME "1.0" --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set BROWSER "Google Chrome" --allow-new
  "$BATS_TEST_DIRNAME/../snapback" config set FOCUS_APPS '("Cursor")' --allow-new
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "snapback volume 0.5 sets VOLUME" {
  snapback volume 0.5
  [ "$(snapback config get VOLUME)" = "0.5" ]
}

@test "snapback volume rejects > 1" {
  run snapback volume 2.0
  [ "$status" -ne 0 ]
}

@test "snapback browser Arc sets BROWSER" {
  snapback browser Arc
  [ "$(snapback config get BROWSER)" = "Arc" ]
}
```

Run: `bats tests/cli_typed.bats`
Expected: `volume`/`browser` tests FAIL (commands don't exist).

- [ ] **Step 2: Implement `cmd_volume` and `cmd_browser`**

Add to `snapback` (before `main`):

```bash
# ============================================================
# VOLUME COMMAND
# ============================================================
cmd_volume() {
  local v="${1:-}"
  if [[ -z "$v" ]]; then
    config_get VOLUME || echo "1.0"
    exit 0
  fi
  # Validate 0.0 <= v <= 1.0
  if ! [[ "$v" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then
    print_error "Invalid volume: $v (expected 0.0 - 1.0)"
    exit 2
  fi
  config_set VOLUME "$v" --allow-new
  print_success "Volume set to: $v"
}

# ============================================================
# BROWSER COMMAND
# ============================================================
cmd_browser() {
  local b="${1:-}"
  if [[ -z "$b" ]]; then
    config_get BROWSER || echo "Google Chrome"
    exit 0
  fi
  config_set BROWSER "$b"
  print_success "Browser set to: $b"
}
```

Wire into `main()`:

```bash
    volume)
      cmd_volume "$@"
      ;;
    browser)
      cmd_browser "$@"
      ;;
```

Update help:
```
  volume [VAL]  Get/set notification volume (0.0 - 1.0)
  browser [NAME]  Get/set browser (e.g., "Google Chrome", Arc, Safari)
```

- [ ] **Step 3: Run tests**

Run: `bats tests/cli_typed.bats`
Expected: volume and browser tests PASS.

- [ ] **Step 4: Commit**

```bash
git add snapback tests/cli_typed.bats
git commit -m "feat(cli): snapback volume and snapback browser"
```

### Task F2.2: `snapback focus` (list / add / remove / set)

**Files:**
- Modify: `snapback`
- Modify: `tests/cli_typed.bats`

- [ ] **Step 1: Failing tests**

Append to `tests/cli_typed.bats`:

```bash
@test "snapback focus list prints current apps" {
  run snapback focus list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor"* ]]
}

@test "snapback focus add appends" {
  snapback focus add Ghostty
  run snapback focus list
  [[ "$output" == *"Cursor"* ]]
  [[ "$output" == *"Ghostty"* ]]
}

@test "snapback focus remove drops the app" {
  snapback focus add Ghostty
  snapback focus remove Cursor
  run snapback focus list
  [[ "$output" != *"Cursor"* ]]
  [[ "$output" == *"Ghostty"* ]]
}

@test "snapback focus set replaces the array" {
  snapback focus set Zed Terminal
  run snapback focus list
  [[ "$output" == *"Zed"* ]]
  [[ "$output" == *"Terminal"* ]]
  [[ "$output" != *"Cursor"* ]]
}
```

Run: `bats tests/cli_typed.bats`
Expected: focus tests FAIL.

- [ ] **Step 2: Implement `cmd_focus`**

Add to `snapback`:

```bash
# ============================================================
# FOCUS COMMAND
# ============================================================
_focus_escape_token() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\$/\\\$}"
  v="${v//\`/\\\`}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

_focus_read_array() {
  # Populate global array FOCUS_APPS from config; empty if unset
  FOCUS_APPS=()
  [[ -f "$CONFIG_FILE" ]] || return 0
  # Source in subshell-safe way: use a temporary
  (
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" 2>/dev/null
    for a in "${FOCUS_APPS[@]}"; do printf '%s\n' "$a"; done
  ) | while IFS= read -r line; do
    FOCUS_APPS+=("$line")
  done
}

_focus_write_array() {
  local literal='('
  local a
  for a in "$@"; do
    literal+="$(_focus_escape_token "$a") "
  done
  literal="${literal% })"
  config_set FOCUS_APPS "$literal"
}

cmd_focus() {
  local sub="${1:-list}"
  shift || true
  # Snapshot current list
  local apps=()
  if [[ -f "$CONFIG_FILE" ]]; then
    mapfile -t apps < <(
      source "$CONFIG_FILE" 2>/dev/null
      for a in "${FOCUS_APPS[@]}"; do printf '%s\n' "$a"; done
    )
  fi
  case "$sub" in
    list)
      for a in "${apps[@]}"; do printf '%s\n' "$a"; done
      ;;
    add)
      [[ $# -ge 1 ]] || { print_error "Usage: snapback focus add NAME"; exit 2; }
      local new="$1"
      for a in "${apps[@]}"; do
        [[ "$a" == "$new" ]] && { print_info "Already present: $new"; exit 0; }
      done
      apps+=("$new")
      _focus_write_array "${apps[@]}"
      print_success "Added: $new"
      ;;
    remove)
      [[ $# -ge 1 ]] || { print_error "Usage: snapback focus remove NAME"; exit 2; }
      local drop="$1" kept=() changed=0
      for a in "${apps[@]}"; do
        if [[ "$a" == "$drop" ]]; then changed=1; else kept+=("$a"); fi
      done
      if (( changed == 0 )); then
        print_warning "Not present: $drop"
        exit 0
      fi
      _focus_write_array "${kept[@]}"
      print_success "Removed: $drop"
      ;;
    set)
      [[ $# -ge 1 ]] || { print_error "Usage: snapback focus set NAME [NAME ...]"; exit 2; }
      _focus_write_array "$@"
      print_success "Focus apps set to: $*"
      ;;
    *)
      print_error "Unknown focus subcommand: $sub"
      exit 2
      ;;
  esac
}
```

Note: `mapfile` requires bash 4; macOS has bash 3.2. Replace with:

```bash
    local apps=()
    if [[ -f "$CONFIG_FILE" ]]; then
      while IFS= read -r line; do
        apps+=("$line")
      done < <(
        source "$CONFIG_FILE" 2>/dev/null
        for a in "${FOCUS_APPS[@]}"; do printf '%s\n' "$a"; done
      )
    fi
```

Wire into `main()`:

```bash
    focus)
      cmd_focus "$@"
      ;;
```

Update help:
```
  focus <sub>   list | add NAME | remove NAME | set NAME1 NAME2 ...
```

- [ ] **Step 3: Run tests**

Run: `bats tests/cli_typed.bats`
Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add snapback tests/cli_typed.bats
git commit -m "feat(cli): snapback focus list|add|remove|set"
```

### Task F2.3: `snapback test` + extract `_play_notification` helper

**Files:**
- Modify: `snapback`
- Modify: `snapback.sh`
- Modify: `tests/cli_typed.bats`

- [ ] **Step 1: Failing test**

Append to `tests/cli_typed.bats`:

```bash
@test "snapback test exits 0 when config is valid" {
  # Use a silent sound to avoid terminal noise
  snapback config set NOTIFICATION_SOUND ""
  run snapback test
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Extract `_play_notification` in `snapback.sh`**

Near the top of `snapback.sh`, after the config-load block, add:

```bash
# Play the configured notification sound at the effective volume.
# Silent no-op if NOTIFICATION_SOUND is empty or missing.
_play_notification() {
  [[ -n "$NOTIFICATION_SOUND" && -f "$NOTIFICATION_SOUND" ]] || return 0
  local sysVol effectiveVol
  sysVol=$(osascript -e "output volume of (get volume settings)" 2>/dev/null || echo 100)
  effectiveVol=$(echo "$VOLUME * $sysVol / 100" | bc -l 2>/dev/null || echo "$VOLUME")
  afplay -v "$effectiveVol" "$NOTIFICATION_SOUND" &
}
```

Replace each of the three inline `sysVol=$(...)` + `afplay` blocks in `snapback.sh` (fast path, frontmost-matches shortcut, full flow) with a call to `_play_notification`. No behavior change.

- [ ] **Step 3: Add `cmd_test` in `snapback`**

```bash
# ============================================================
# TEST COMMAND
# ============================================================
cmd_test() {
  [[ -f "$CONFIG_FILE" ]] || { print_error "Config not found"; exit 1; }
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  # Resolve "default"
  if [[ "${NOTIFICATION_SOUND:-}" == "default" ]]; then
    NOTIFICATION_SOUND="$SCRIPT_DIR/notification.mp3"
  fi
  if [[ -z "${NOTIFICATION_SOUND:-}" ]]; then
    print_info "NOTIFICATION_SOUND is empty — no sound to play."
    exit 0
  fi
  if [[ ! -f "$NOTIFICATION_SOUND" ]]; then
    print_error "Sound file not found: $NOTIFICATION_SOUND"
    exit 1
  fi
  local sysVol effectiveVol
  sysVol=$(osascript -e "output volume of (get volume settings)" 2>/dev/null || echo 100)
  effectiveVol=$(echo "${VOLUME:-1.0} * $sysVol / 100" | bc -l 2>/dev/null || echo "${VOLUME:-1.0}")
  afplay -v "$effectiveVol" "$NOTIFICATION_SOUND"
  print_success "Played $NOTIFICATION_SOUND at ${effectiveVol}"
}
```

Wire into `main()`:

```bash
    test)
      cmd_test
      ;;
```

Update help:
```
  test          Play a notification preview at the current volume
```

- [ ] **Step 4: Run tests**

Run: `bats tests/cli_typed.bats`
Expected: test passes.

- [ ] **Step 5: Manual smoke test**

```bash
./snapback test
# Should hear the notification.mp3 (or a message about missing sound).
```

- [ ] **Step 6: Commit**

```bash
git add snapback snapback.sh tests/cli_typed.bats
git commit -m "feat(cli): snapback test; dedupe sound playback into _play_notification"
```

---

## Phase F3 — Menu-bar refactor

**All of F3 is blocked until F2 lands — the menu-bar shells out to the new typed commands.**

### Task F3.1: `ShellCommand` — argv runner, PATH augmentation, exit code

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Utilities/ShellCommand.swift`

- [ ] **Step 1: Rewrite `ShellCommand.swift`**

Replace the entire file contents with:

```swift
import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

struct ShellCommand {
    /// Explicit argv execution — no shell parsing. Used for all writes.
    @discardableResult
    static func run(executable: String, args: [String]) -> ShellResult {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe

        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // Prepend common user-install locations that are missing from LaunchAgent PATH.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:\(existingPath)"
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ShellResult(stdout: "", stderr: "spawn failed: \(error)", exitCode: -1)
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ShellResult(stdout: out, stderr: err, exitCode: process.terminationStatus)
    }

    /// Legacy shell pipeline runner.  Keep ONLY for on/off flows; do not
    /// pass user-controlled strings here.
    @discardableResult
    static func runShell(_ command: String) -> String {
        let result = run(executable: "/bin/bash", args: ["-c", command])
        return result.stdout
    }
}
```

- [ ] **Step 2: Fix up the two existing call-sites so they compile**

Find `ShellCommand.run("snapback \(command)")` in `AppState.swift` (`toggleEnabled`) → it's shell-style; keep it on `runShell` for now (F3.2 rewrites it):

```swift
ShellCommand.runShell("snapback \(command)")
```

Find `ShellCommand.run(...)` in `playTestSound` → likewise `runShell` (also rewritten in F3.6).

- [ ] **Step 3: Build**

```bash
cd SnapBackApp && swift build -c release && cd ..
```
Expected: builds with no errors.

- [ ] **Step 4: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Utilities/ShellCommand.swift SnapBackApp/Sources/SnapBackApp/Models/AppState.swift
git commit -m "refactor(menubar): ShellCommand argv runner + PATH augmentation"
```

### Task F3.2: `SnapBackCLI` service — binary resolution + typed methods

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Services/SnapBackCLI.swift`

- [ ] **Step 1: Create the service**

```swift
import Foundation

final class SnapBackCLI {
    /// Absolute path to the `snapback` executable, or nil if not found.
    let executablePath: String?

    init() {
        self.executablePath = Self.resolve()
    }

    private static func resolve() -> String? {
        // 1. Info.plist override (set by build-app.sh at build time).
        if let override = Bundle.main.object(forInfoDictionaryKey: "SnapBackCLIPath") as? String,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        // 2. Hardcoded candidate list.
        let candidates = [
            "/usr/local/bin/snapback",
            "/opt/homebrew/bin/snapback",
            "\(NSHomeDirectory())/.local/bin/snapback",
            "\(NSHomeDirectory())/.snapback/snapback",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                // realpath-style resolution
                if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
                    // If relative, resolve against the symlink directory
                    if resolved.hasPrefix("/") { return resolved }
                    let dir = (path as NSString).deletingLastPathComponent
                    return (dir as NSString).appendingPathComponent(resolved)
                }
                return path
            }
        }
        return nil
    }

    /// Execute `snapback` with the given args.  Returns nil if the CLI is not found.
    @discardableResult
    func run(_ args: [String]) -> ShellResult? {
        guard let path = executablePath else { return nil }
        return ShellCommand.run(executable: path, args: args)
    }

    // Typed wrappers — one per mutation.
    func setVolume(_ v: Double) -> ShellResult? { run(["volume", String(format: "%.2f", v)]) }
    func setMode(_ m: String) -> ShellResult? { run(["mode", m]) }
    func setBrowser(_ b: String) -> ShellResult? { run(["browser", b]) }
    func setFocusApps(_ apps: [String]) -> ShellResult? { run(["focus", "set"] + apps) }
    func setThrottle(_ s: Int) -> ShellResult? { run(["config", "set", "THROTTLE_SECONDS", String(s)]) }
    func setSeekBack(_ s: Int) -> ShellResult? { run(["config", "set", "SEEK_BACK_SECONDS", String(s)]) }
    func test() -> ShellResult? { run(["test"]) }
    func on() -> ShellResult? { run(["on"]) }
    func off() -> ShellResult? { run(["off"]) }
}
```

- [ ] **Step 2: Build**

```bash
cd SnapBackApp && swift build -c release && cd ..
```
Expected: builds.

- [ ] **Step 3: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Services/SnapBackCLI.swift
git commit -m "feat(menubar): SnapBackCLI service with binary resolution"
```

### Task F3.3: Rewrite `AppState` setters + extend `loadConfig`

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Models/AppState.swift`

- [ ] **Step 1: Inject `SnapBackCLI` and add `@Published var lastError`**

At the top of `AppState`:

```swift
let cli = SnapBackCLI()

@Published var lastError: String? = nil

/// Timestamp of the last outgoing write — used by ConfigWatcher to suppress echo.
private(set) var lastOutgoingWriteAt: Date? = nil
```

- [ ] **Step 2: Replace `saveConfig()` with per-key setters**

Remove the old `saveConfig()` stub. Add:

```swift
private func writeResult(_ result: ShellResult?, label: String) {
    guard let result else {
        DispatchQueue.main.async { self.lastError = "SnapBack CLI not found" }
        return
    }
    lastOutgoingWriteAt = Date()
    if result.exitCode != 0 {
        let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async { self.lastError = "\(label): \(msg.isEmpty ? "exit \(result.exitCode)" : msg)" }
    } else {
        DispatchQueue.main.async { self.lastError = nil }
    }
}

private var debouncers: [String: DispatchWorkItem] = [:]
private let debounceQueue = DispatchQueue(label: "com.snapback.debounce")

private func debounced(_ key: String, _ action: @escaping () -> Void) {
    debounceQueue.async { [weak self] in
        self?.debouncers[key]?.cancel()
        let item = DispatchWorkItem(block: action)
        self?.debouncers[key] = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2, execute: item)
    }
}

func setVolume(_ v: Double) {
    volume = v  // optimistic UI
    debounced("volume") { [weak self] in
        guard let self else { return }
        self.writeResult(self.cli.setVolume(v), label: "volume")
    }
}
func setMode(_ m: String) {
    mode = m
    debounced("mode") { [weak self] in
        guard let self else { return }
        self.writeResult(self.cli.setMode(m), label: "mode")
    }
}
func setBrowser(_ b: String) {
    browser = b
    debounced("browser") { [weak self] in
        guard let self else { return }
        self.writeResult(self.cli.setBrowser(b), label: "browser")
    }
}
func setFocusApps(_ apps: [String]) {
    focusApps = apps
    debounced("focus") { [weak self] in
        guard let self else { return }
        self.writeResult(self.cli.setFocusApps(apps), label: "focus")
    }
}
func setThrottle(_ s: Int) {
    throttleSeconds = s
    debounced("throttle") { [weak self] in
        guard let self else { return }
        self.writeResult(self.cli.setThrottle(s), label: "throttle")
    }
}
func setSeekBack(_ s: Int) {
    seekBackSeconds = s
    debounced("seekBack") { [weak self] in
        guard let self else { return }
        self.writeResult(self.cli.setSeekBack(s), label: "seekBack")
    }
}
```

Update `addFocusApp` and `removeFocusApp` to call `setFocusApps`:

```swift
func addFocusApp(_ app: String) {
    if !focusApps.contains(app) {
        setFocusApps(focusApps + [app])
    }
}
func removeFocusApp(_ app: String) {
    setFocusApps(focusApps.filter { $0 != app })
}
func moveFocusApp(_ app: String, by offset: Int) {
    guard let idx = focusApps.firstIndex(of: app) else { return }
    let newIdx = max(0, min(focusApps.count - 1, idx + offset))
    guard newIdx != idx else { return }
    var arr = focusApps
    arr.remove(at: idx)
    arr.insert(app, at: newIdx)
    setFocusApps(arr)
}
```

- [ ] **Step 3: Extend `loadConfig()` to read `FOCUS_DELAY` and `NOTIFICATION_SOUND`**

Add properties to `AppState`:

```swift
@Published var focusDelay: Double = 0.5
@Published var notificationSound: String = "default"
```

Extend `loadConfig()` parsing:

```swift
} else if let match = parseConfigLine(trimmed, key: "FOCUS_DELAY") {
    focusDelay = Double(match) ?? 0.5
} else if let match = parseConfigLine(trimmed, key: "NOTIFICATION_SOUND") {
    notificationSound = match
}
```

- [ ] **Step 4: Harden `parseConfigLine` for escaped double-quotes**

Replace the existing `parseConfigLine` with:

```swift
private func parseConfigLine(_ line: String, key: String) -> String? {
    guard line.hasPrefix("\(key)=") else { return nil }
    var value = String(line.dropFirst(key.count + 1))
    // Strip at most one pair of surrounding double quotes.
    if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
        value = String(value.dropFirst().dropLast())
    }
    // Unescape the four bytes we escape on write: \\ \$ \` \"
    var out = ""
    var i = value.startIndex
    while i < value.endIndex {
        let c = value[i]
        if c == "\\" {
            let next = value.index(after: i)
            if next < value.endIndex {
                let n = value[next]
                if n == "\\" || n == "$" || n == "`" || n == "\"" {
                    out.append(n)
                    i = value.index(after: next)
                    continue
                }
            }
        }
        out.append(c)
        i = value.index(after: i)
    }
    return out
}
```

- [ ] **Step 5: Update `parseFocusApps` to honour the same escape grammar**

Replace with:

```swift
private func parseFocusApps(_ line: String) -> [String] {
    guard let start = line.firstIndex(of: "("),
          let end = line.lastIndex(of: ")") else { return [] }
    let inner = String(line[line.index(after: start)..<end])

    var apps: [String] = []
    var current = ""
    var inQuotes = false
    var escaped = false

    for char in inner {
        if escaped {
            current.append(char)
            escaped = false
            continue
        }
        if char == "\\" && inQuotes {
            escaped = true
            continue
        }
        if char == "\"" {
            if inQuotes {
                apps.append(current)
                current = ""
            }
            inQuotes.toggle()
            continue
        }
        if inQuotes {
            current.append(char)
        }
    }
    return apps
}
```

- [ ] **Step 6: Rewrite `toggleEnabled` to use the CLI service**

```swift
func toggleEnabled() {
    let wasEnabled = isEnabled
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else { return }
        let result = wasEnabled ? self.cli.off() : self.cli.on()
        DispatchQueue.main.async {
            if result == nil { self.lastError = "SnapBack CLI not found" }
            else if result!.exitCode != 0 {
                self.lastError = "toggle: exit \(result!.exitCode)"
            }
            self.checkHooksEnabled()
        }
    }
}
```

- [ ] **Step 7: Replace `playTestSound` with CLI call**

```swift
func playTestSound() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else { return }
        self.writeResult(self.cli.test(), label: "test")
    }
}
```

- [ ] **Step 8: Build**

```bash
cd SnapBackApp && swift build -c release && cd ..
```
Expected: builds.

- [ ] **Step 9: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Models/AppState.swift
git commit -m "refactor(menubar): per-key setters via CLI; extended loadConfig; hardened parsers"
```

### Task F3.4: `ConfigWatcher` with echo suppression

**Files:**
- Create: `SnapBackApp/Sources/SnapBackApp/Services/ConfigWatcher.swift`
- Modify: `SnapBackApp/Sources/SnapBackApp/Models/AppState.swift`

- [ ] **Step 1: Create the watcher**

```swift
import Foundation

final class ConfigWatcher {
    private let path: String
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "com.snapback.configWatcher")
    private let onChange: () -> Void
    /// Closure returning the timestamp of the most recent write we made.
    private let lastOwnWriteAt: () -> Date?

    init(path: String, onChange: @escaping () -> Void, lastOwnWriteAt: @escaping () -> Date?) {
        self.path = path
        self.onChange = onChange
        self.lastOwnWriteAt = lastOwnWriteAt
        start()
    }

    deinit { stop() }

    private func start() {
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Echo-suppress writes we made ourselves.
            if let ts = self.lastOwnWriteAt(), Date().timeIntervalSince(ts) < 0.5 {
                // Still re-arm on rename/delete
                self.rearmIfNeeded(src: src)
                return
            }
            self.onChange()
            self.rearmIfNeeded(src: src)
        }
        src.setCancelHandler { [weak self] in
            guard let self = self, self.fd >= 0 else { return }
            close(self.fd)
            self.fd = -1
        }
        src.resume()
        self.source = src
    }

    private func rearmIfNeeded(src: DispatchSourceFileSystemObject) {
        // Atomic renames replace the inode, so our fd becomes stale.
        // Cancel + restart on rename/delete.
        let data = src.data
        if data.contains(.rename) || data.contains(.delete) {
            stop()
            // Small delay so the new file is settled before we reopen.
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.start()
            }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
```

- [ ] **Step 2: Wire the watcher into `AppState`**

Add a property:

```swift
private var watcher: ConfigWatcher?
```

Extend `init()`:

```swift
init() {
    loadConfig()
    checkHooksEnabled()
    checkLoginItemStatus()
    watcher = ConfigWatcher(
        path: configPath,
        onChange: { [weak self] in
            DispatchQueue.main.async { self?.loadConfig() }
        },
        lastOwnWriteAt: { [weak self] in self?.lastOutgoingWriteAt }
    )
}
```

- [ ] **Step 3: Build**

```bash
cd SnapBackApp && swift build -c release && cd ..
```

- [ ] **Step 4: Manual smoke test**

Build and launch the `.app`, then in a terminal run `snapback volume 0.4`. Menu-bar volume slider should update within a second without triggering outgoing writes.

- [ ] **Step 5: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Services/ConfigWatcher.swift SnapBackApp/Sources/SnapBackApp/Models/AppState.swift
git commit -m "feat(menubar): ConfigWatcher with echo suppression"
```

### Task F3.5: Re-enable controls, add error banner, add focus-app reorder

**Files:**
- Modify: `SnapBackApp/Sources/SnapBackApp/Views/MenuBarView.swift`
- Modify: `SnapBackApp/Sources/SnapBackApp/Views/FocusAppsView.swift`

- [ ] **Step 1: Remove `.disabled(true)` from mutating controls in `MenuBarView`**

Revert the F0b disables on: volume `Slider` and test button; mode `Picker`; browser `Picker`, throttle `Stepper`, seek-back `Stepper`.

- [ ] **Step 2: Rewire bindings to go through setters**

Change `Slider(value: $appState.volume, ...)`:

```swift
Slider(value: Binding(get: { appState.volume },
                      set: { appState.setVolume($0) }), in: 0...1)
```

Similarly for mode picker, browser picker, throttle stepper, seek-back stepper — use `Binding(get:set:)` that calls the corresponding `set...` method.

Remove `.onChange(of: appState.volume) { _ in appState.saveConfig() }` and equivalents (no longer needed).

- [ ] **Step 3: Add the error banner**

At the top of the main `VStack` in `MenuBarView.body`, before `headerSection`:

```swift
if let err = appState.lastError {
    Text(err)
        .font(.system(size: 11))
        .foregroundColor(.red)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
}
```

- [ ] **Step 4: Add effective-volume readout**

In `volumeSection`, alongside the percentage label, show the effective volume (requires a helper on `AppState` that queries system volume via `osascript`, or fetched periodically). For simplicity, just show the configured VOLUME × 100%; the system-volume multiplication is runtime-only and not surfaced. Leave the existing `\(Int(appState.volume * 100))%`.

(Deferred: a full system-volume readout would need a poller; out of scope for this task.)

- [ ] **Step 4.5: Add Safari to the browser picker**

In `MenuBarView.swift`'s `settingsSection`, the `Picker` for browser currently lists Chrome/Arc/Firefox/Brave. Add Safari:

```swift
Picker("", selection: Binding(
    get: { appState.browser },
    set: { appState.setBrowser($0) }
)) {
    Text("Chrome").tag("Google Chrome")
    Text("Safari").tag("Safari")
    Text("Arc").tag("Arc")
    Text("Firefox").tag("Firefox")
    Text("Brave").tag("Brave Browser")
}
```

- [ ] **Step 5: Re-enable and augment `FocusAppsView`**

Remove `.disabled(true)` from the add button and remove button.

Augment `AppChip` with up/down chevrons:

```swift
struct AppChip: View {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if canMoveUp {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            if canMoveDown {
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(name).font(.system(size: 10)).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}
```

Update the `ForEach` in `FocusAppsView` to pass these in:

```swift
ForEach(Array(appState.focusApps.enumerated()), id: \.element) { idx, app in
    AppChip(
        name: app,
        canMoveUp: idx > 0,
        canMoveDown: idx < appState.focusApps.count - 1,
        onMoveUp: { appState.moveFocusApp(app, by: -1) },
        onMoveDown: { appState.moveFocusApp(app, by: 1) },
        onRemove: { appState.removeFocusApp(app) }
    )
}
```

- [ ] **Step 6: Build**

```bash
cd SnapBackApp && swift build -c release && cd ..
```

- [ ] **Step 7: Manual smoke test**

Build `.app`, launch it, verify:
- Sliders/pickers mutate and persist (check with `snapback config show`)
- External CLI edit (`snapback volume 0.3`) updates the UI
- Moving focus apps with chevrons writes the expected array
- Invalid state (e.g., `/Applications/SnapBack.app` run without `snapback` on PATH) shows the red banner

- [ ] **Step 8: Commit**

```bash
git add SnapBackApp/Sources/SnapBackApp/Views/MenuBarView.swift SnapBackApp/Sources/SnapBackApp/Views/FocusAppsView.swift
git commit -m "feat(menubar): enable controls via CLI setters, error banner, chip reorder"
```

### Task F3.6: Stamp `SnapBackCLIPath` into `Info.plist` at build time

**Files:**
- Modify: `SnapBackApp/build-app.sh`

- [ ] **Step 1: Accept an optional CLI path argument**

Replace the `Info.plist` heredoc in `build-app.sh` with a two-step approach: write a base plist, then patch in the CLI path if provided.

```bash
SNAPBACK_CLI_PATH="${SNAPBACK_CLI_PATH:-}"  # set by install.sh when known

cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SnapBack</string>
    <key>CFBundleIdentifier</key><string>com.snapback.menubar</string>
    <key>CFBundleName</key><string>SnapBack</string>
    <key>CFBundleDisplayName</key><string>SnapBack</string>
    <key>CFBundleVersion</key><string>1.2</string>
    <key>CFBundleShortVersionString</key><string>1.2</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

if [[ -n "$SNAPBACK_CLI_PATH" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SnapBackCLIPath string $SNAPBACK_CLI_PATH" \
    "$APP_BUNDLE/Contents/Info.plist"
fi
```

- [ ] **Step 2: Build and verify the key lands when provided**

```bash
SNAPBACK_CLI_PATH=/usr/local/bin/snapback ./SnapBackApp/build-app.sh
/usr/libexec/PlistBuddy -c "Print :SnapBackCLIPath" SnapBackApp/SnapBack.app/Contents/Info.plist
```
Expected: prints `/usr/local/bin/snapback`.

- [ ] **Step 3: Commit**

```bash
git add SnapBackApp/build-app.sh
git commit -m "feat(menubar): stamp SnapBackCLIPath into Info.plist when provided"
```

---

## Phase F4 — Distribution + polish

### Task F4.1: `install.sh` menu-bar build prompt

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add a new section after the permissions probe**

```bash
# ============================================================
# MENU-BAR APP (optional)
# ============================================================
echo ""
if command -v swift &>/dev/null && [[ -d "$SCRIPT_DIR/SnapBackApp" ]]; then
  install_app=""
  if [[ "$AUTO_YES" == "true" ]]; then
    install_app="n"  # default no for non-interactive
  else
    ask "Build & install SnapBack menu-bar app? [Y/n]: " "Y" install_app
  fi

  case "$install_app" in
    [Yy]*)
      print_info "Building menu-bar app..."
      (
        cd "$SCRIPT_DIR/SnapBackApp"
        # Point the bundle at the CLI we just symlinked (prefer /usr/local/bin)
        export SNAPBACK_CLI_PATH=""
        for p in /usr/local/bin/snapback /opt/homebrew/bin/snapback "$HOME/.local/bin/snapback"; do
          if [[ -x "$p" ]]; then SNAPBACK_CLI_PATH="$p"; break; fi
        done
        ./build-app.sh
      )
      print_info "Installing to /Applications/SnapBack.app ..."
      if [[ -w /Applications ]]; then
        rm -rf /Applications/SnapBack.app
        cp -R "$SCRIPT_DIR/SnapBackApp/SnapBack.app" /Applications/
      else
        sudo rm -rf /Applications/SnapBack.app
        sudo cp -R "$SCRIPT_DIR/SnapBackApp/SnapBack.app" /Applications/
      fi
      print_success "Installed. Run with: snapback app (or from /Applications)"
      ;;
    *)
      print_info "Skipped. Re-run 'snapback update' any time to install."
      ;;
  esac
else
  if ! command -v swift &>/dev/null; then
    print_info "Menu-bar app skipped (Swift not available)."
    print_info "Install Xcode Command Line Tools: xcode-select --install"
  fi
fi
```

- [ ] **Step 2: Manual smoke test**

```bash
./install.sh -y   # skips menu-bar (auto-yes defaults no)
./install.sh      # prompts; say y
ls /Applications/SnapBack.app >/dev/null && echo OK
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): optional menu-bar app build prompt"
```

### Task F4.2: `snapback update` rebuilds menu-bar + tarball includes `SnapBackApp/`

**Files:**
- Modify: `snapback`

- [ ] **Step 1: Fix the tarball copy inside `cmd_update`**

In `cmd_update`, the tarball branch currently copies only 4 shell files. Extend to:

```bash
      cp "$tmp_dir/snapback" "$install_dir/"
      cp "$tmp_dir/snapback.sh" "$install_dir/"
      cp "$tmp_dir/snapback-resume.sh" "$install_dir/"
      cp "$tmp_dir/snapback-lib.sh" "$install_dir/"
      cp "$tmp_dir/install.sh" "$install_dir/"
      cp "$tmp_dir/notification.mp3" "$install_dir/" 2>/dev/null || true
      rm -rf "$install_dir/SnapBackApp"
      cp -R "$tmp_dir/SnapBackApp" "$install_dir/"
      chmod +x "$install_dir/snapback" "$install_dir/snapback.sh" \
               "$install_dir/snapback-resume.sh" "$install_dir/install.sh" \
               "$install_dir/SnapBackApp/build-app.sh"
```

- [ ] **Step 2: Add menu-bar rebuild step at the end of `cmd_update`**

```bash
  # Menu-bar app maintenance
  local app_installed="/Applications/SnapBack.app"
  if [[ -d "$install_dir/SnapBackApp" ]] && command -v swift &>/dev/null; then
    if [[ -d "$app_installed" ]]; then
      print_info "Rebuilding menu-bar app..."
      (
        cd "$install_dir/SnapBackApp"
        for p in /usr/local/bin/snapback /opt/homebrew/bin/snapback "$HOME/.local/bin/snapback"; do
          [[ -x "$p" ]] && export SNAPBACK_CLI_PATH="$p" && break
        done
        ./build-app.sh
      )
      if [[ -w /Applications ]]; then
        rm -rf "$app_installed"
        cp -R "$install_dir/SnapBackApp/SnapBack.app" "$app_installed"
      else
        sudo rm -rf "$app_installed"
        sudo cp -R "$install_dir/SnapBackApp/SnapBack.app" "$app_installed"
      fi
      print_success "Menu-bar app rebuilt"
    else
      # Offer to install now, respecting non-TTY
      if [[ -t 0 ]]; then
        read -p "Menu-bar app not installed. Install now? [y/N]: " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
          (cd "$install_dir/SnapBackApp" && ./build-app.sh)
          if [[ -w /Applications ]]; then
            cp -R "$install_dir/SnapBackApp/SnapBack.app" "$app_installed"
          else
            sudo cp -R "$install_dir/SnapBackApp/SnapBack.app" "$app_installed"
          fi
          print_success "Menu-bar app installed"
        fi
      fi
    fi
  elif [[ -d "$install_dir/SnapBackApp" ]]; then
    print_info "Menu-bar app present but Swift not available — install Xcode Command Line Tools to build."
  fi
```

- [ ] **Step 3: Commit**

```bash
git add snapback
git commit -m "feat(cli): snapback update copies SnapBackApp and rebuilds menu-bar"
```

### Task F4.3: `snapback uninstall` removes `/Applications/SnapBack.app`, `snapback status` reports menu-bar

**Files:**
- Modify: `snapback`

- [ ] **Step 1: Extend `cmd_uninstall`**

After the `rm -rf "$CONFIG_DIR"` block:

```bash
  # Remove menu-bar app if installed
  if [[ -d "/Applications/SnapBack.app" ]]; then
    read -p "Remove /Applications/SnapBack.app? [y/N]: " rm_app
    if [[ "$rm_app" =~ ^[Yy]$ ]]; then
      if [[ -w /Applications/SnapBack.app ]]; then
        rm -rf /Applications/SnapBack.app
      else
        sudo rm -rf /Applications/SnapBack.app
      fi
      print_success "Removed /Applications/SnapBack.app"
    fi
  fi
```

- [ ] **Step 2: Extend `cmd_status`**

Before the final summary in `cmd_status`:

```bash
  # Menu-bar app status
  echo ""
  echo "Menu-bar app"
  echo "────────────"
  if [[ -d "/Applications/SnapBack.app" ]]; then
    print_success "Installed at /Applications/SnapBack.app"
    if pgrep -x SnapBack >/dev/null 2>&1; then
      print_info "  Running"
    else
      print_info "  Not running (launch with: snapback app)"
    fi
  else
    print_info "Not installed (run 'snapback update' with Swift available to install)"
  fi

  # Effective volume (configured VOLUME × system volume)
  if [[ -f "$CONFIG_FILE" ]]; then
    local configured_vol sys_vol effective_pct
    configured_vol=$(config_get VOLUME 2>/dev/null || echo "1.0")
    sys_vol=$(osascript -e "output volume of (get volume settings)" 2>/dev/null || echo "100")
    effective_pct=$(echo "$configured_vol * $sys_vol" | bc -l 2>/dev/null | awk '{printf "%.0f", $1}')
    echo ""
    print_info "Effective volume: ${configured_vol} × ${sys_vol}% = ${effective_pct}%"
  fi
```

- [ ] **Step 3: Commit**

```bash
git add snapback
git commit -m "feat(cli): uninstall removes menu-bar app; status reports menu-bar state"
```

### Task F4.4: Version bump to 1.2.0, help text, README, ROADMAP

**Files:**
- Modify: `snapback` (VERSION + help)
- Modify: `README.md`
- Modify: `ROADMAP.md`

- [ ] **Step 1: Bump version**

In `snapback`, change `VERSION="1.1.0"` to `VERSION="1.2.0"`.

- [ ] **Step 2: Finalize help text**

Replace `show_help()`'s Commands block with:

```
Commands:
  install [-y]  Interactive installation and configuration
  status        Check configuration and menu-bar state
  on            Enable Claude Code hooks
  off           Disable Claude Code hooks (keeps config)
  mode [MODE]   Get/set mode: full (sound + focus) or sound (sound only)
  volume [VAL]  Get/set notification volume (0.0 - 1.0)
  browser [NAME]  Get/set browser (Google Chrome, Arc, Safari, Firefox, Brave)
  focus <sub>   list | add NAME | remove NAME | set NAME1 NAME2 ...
  config <sub>  get KEY | set KEY VAL [--allow-new] | show [--json] | path
  test          Play a notification preview
  app           Launch the menu-bar app (if installed)
  update        Update to latest version (and rebuild menu-bar app if installed)
  uninstall     Remove config, hooks, and menu-bar app
  help          Show this help message
```

- [ ] **Step 3: Update `README.md`**

In the existing Commands section of the README (or wherever the CLI is documented), add the new rows for `volume`, `browser`, `focus`, `config`, `test`, `app`, and mention the menu-bar app in one short paragraph:

```markdown
### Menu-bar app (optional)

SnapBack ships with an optional SwiftUI menu-bar app that lets you tweak
volume, mode, focus apps, and the Claude Code on/off switch without a
terminal. It's built locally from source during `snapback install`
(requires Xcode Command Line Tools / Swift 5.9+, macOS 13+). Open with
`snapback app` or from `/Applications/SnapBack.app`.
```

- [ ] **Step 4: Update `ROADMAP.md`**

Move `macOS menubar app with on/off toggle` from the "Nice to Have" section to "Completed".

- [ ] **Step 5: Final verification**

```bash
./snapback --version
# → SnapBack v1.2.0

./snapback help
# → new help text visible
```

- [ ] **Step 6: Commit**

```bash
git add snapback README.md ROADMAP.md
git commit -m "chore: bump version to 1.2.0; update README and ROADMAP"
```

### Task F4.5: Final manual smoke test and push

**Files:** none (verification only)

- [ ] **Step 1: Fresh-install simulation**

```bash
# Save real state
cp -R ~/.snapback ~/.snapback.bak 2>/dev/null || true
cp -R ~/.config/snapback ~/.config/snapback.bak 2>/dev/null || true
[[ -d /Applications/SnapBack.app ]] && sudo mv /Applications/SnapBack.app /Applications/SnapBack.app.bak

rm -rf ~/.snapback ~/.config/snapback

# Simulate curl | bash (use local clone instead of fetching)
bash get.sh
# Walk through the prompts, say Y to menu-bar app
```

- [ ] **Step 2: Verify everything**

```bash
snapback status
snapback config show
snapback volume 0.3
snapback focus list
snapback test
open /Applications/SnapBack.app
```

- [ ] **Step 3: Restore state**

```bash
rm -rf ~/.snapback ~/.config/snapback
mv ~/.snapback.bak ~/.snapback 2>/dev/null || true
mv ~/.config/snapback.bak ~/.config/snapback 2>/dev/null || true
[[ -d /Applications/SnapBack.app.bak ]] && sudo mv /Applications/SnapBack.app.bak /Applications/SnapBack.app
```

- [ ] **Step 4: Push**

```bash
git log --oneline -20
git push origin main
```

---

## Post-implementation check

- `git status` clean.
- `snapback --version` prints `1.2.0`.
- `bats tests/` passes (`bats tests/config_set.bats tests/cli_typed.bats`).
- Menu-bar app builds, launches, and all controls round-trip through the CLI.
- README, ROADMAP, help text consistent.
