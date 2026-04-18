# SnapBack Unification — Design

Date: 2026-04-18
Status: Draft — awaiting user approval
Target version: 1.2.0

## 1. Motivation

The repository is currently in a half-finished state:

- Uncommitted changes introduce `VOLUME`, a fast-path for `MODE=sound`, and an `app` subcommand.
- An untracked SwiftUI menu-bar app (`SnapBackApp/`) exists with three real bugs and no distribution path.
- The CLI and the menu-bar app both write the config file, with different writers and different coverage.
- `install.sh` uses yet a third writer that drops `MODE` and `VOLUME` on reconfigure.
- Build artifacts (`.build/`, `SnapBack.app/`, `.DS_Store`) are untracked but unignored.

Goal: unify CLI and menu-bar into one coherent product, fix the underlying bugs, and ship 1.2.0.

## 2. Problems to fix

### 2.1 Scattered config writers

Three independent writers touch `~/.config/snapback/config`:

1. `install.sh` — heredoc regenerates whole file; drops any unknown/extra keys (including the new `MODE`, `VOLUME`).
2. `snapback` CLI `cmd_mode` — `sed`-based scalar replacement, correct but only for `MODE`.
3. `SnapBackApp/Sources/.../AppState.swift:saveConfig()` — regenerates whole file from in-memory struct; hardcodes `FOCUS_DELAY=0.5` and `NOTIFICATION_SOUND="default"`; silently loses any custom values the user wrote by hand.

Result: the same key written from two UIs can produce different files, and hand edits are unsafe.

### 2.2 CLI / menu-bar asymmetry

Menu-bar exposes: volume, mode, focus apps (add/remove), browser (from hardcoded list), throttle, seek back, login-item toggle.

CLI exposes: only `mode`. No way to set volume, focus apps, browser, throttle, seek back from the terminal.

### 2.3 Menu-bar app bugs

- `AppState.swift:200` hardcodes `~/Documents/Programming/AIAttention/notification.mp3` — works only on the author's machine.
- `AppState.saveConfig()` is destructive (§2.1).
- `playTestSound` reimplements the volume math inline in a shell one-liner, diverging from `snapback.sh`.
- `FocusAppsView` has no reordering — order in the config matters (last app stays on top), so the list must be orderable.
- No observation of external config changes: edits via CLI or `vim` are not reflected until restart.
- `ShellCommand.run` concatenates strings; any config value containing a single quote would break it.

### 2.4 Distribution gap

- `get.sh` / `snapback update` fetch shell scripts only (via tarball branch) or whole repo (via `git clone`). Neither builds the menu-bar app.
- `install.sh` never mentions the menu-bar app.
- `snapback app` assumes `/Applications/SnapBack.app` or `$SCRIPT_DIR/SnapBackApp/SnapBack.app` exists — but nothing puts it there.
- No mechanism to keep `/Applications/SnapBack.app` in sync with `snapback update`.

### 2.5 Repo hygiene

- `.gitignore` contains only `.DS_Store`.
- `SnapBackApp/.build/`, `SnapBackApp/SnapBack.app/` are untracked build output.
- `.DS_Store` in repo root despite being in `.gitignore` (already tracked historically? verify during F0).

### 2.6 Hook setup inconsistency

- `install.sh` `setup_hooks` unconditionally overwrites `PermissionRequest`, `Stop`, `UserPromptSubmit` entries → destroys user's other hooks.
- `snapback on` preserves other tools' hooks via a jq `select(... | contains("snapback") | not)` filter.

Normalize both to the preserving behavior.

### 2.7 Installer side-effect

`install.sh` ends with `"$SCRIPT_DIR/snapback.sh"` to trigger permission prompts. In full mode this actually activates the user's IDE and (if a browser is playing) pauses media. It should use a quiet permission probe instead (e.g., a throwaway `osascript` that only asks for System Events access without driving the full flow).

## 3. Target architecture

Four layers, with strict direction:

```
Menubar App          reads config file directly
  │                  observes config file changes
  └─ fork+exec ────▶ CLI (snapback)
                      │
                      ├─ writes via config_set ──▶ ~/.config/snapback/config
                      └─ writes hooks ──▶ ~/.claude/settings.json
                                                │
                                                ▼
                                         snapback.sh / snapback-resume.sh
                                         (runtime, read-only)
```

### Invariant

All mutations of `~/.config/snapback/config` go through a single shell function `config_set KEY VALUE`, defined once in `snapback`. `install.sh` sources it; the menu-bar app calls it via `snapback config set`.

### Read path

- Runtime scripts (`snapback.sh`, `snapback-resume.sh`): unchanged; `source` the config.
- Menu-bar app: parses the config file natively (no shell round-trip needed for reads). On `DispatchSourceFileSystemObject` events, re-parses and publishes changes on `@Published` state.

### Write path

- CLI: calls `config_set` internally.
- Menu-bar app: fork-exec of `snapback config set KEY VALUE` (generic) or `snapback volume VAL` (typed wrapper). Debounced at 200ms per key for sliders/steppers.

## 4. Config API

### 4.1 `config_set KEY VALUE`

Shell function inside `snapback`. Contract:

- **Scalar keys** (default): rewrite the line matching `^KEY=` using `sed`. If the key is absent, append with a default-comment marker. Values are always written with double quotes (`KEY="VALUE"`), which is shell-safe for both strings and numerics (arithmetic still works under `(( ))`).
- **Array keys** (set: `FOCUS_APPS`): awk-based rewrite of the line `FOCUS_APPS=(...)`, expanding `VALUE` as a space-separated list of pre-quoted tokens; the caller passes the array pre-formatted (`"Cursor" "Ghostty"`).
- **Atomic**: write to a tempfile next to config, `mv` into place.
- **Preserve**: comments, blank lines, unknown keys, and line order.
- **Validate**: reject unknown keys unless `--allow-new` is passed; reject empty values unless the key's default empty is legal (`NOTIFICATION_SOUND=""` is legal).

Known keys table (single source in `snapback`):

| Key | Type | Valid values |
|---|---|---|
| `FOCUS_APPS` | array | ≥1 non-empty token |
| `FOCUS_DELAY` | scalar float | `0.0 ≤ x ≤ 5.0` |
| `BROWSER` | scalar string | any |
| `SEEK_BACK_SECONDS` | scalar int | `0 ≤ x ≤ 10` |
| `THROTTLE_SECONDS` | scalar int | `0 ≤ x ≤ 60` |
| `NOTIFICATION_SOUND` | scalar string | `""`, `"default"`, or path to file |
| `VOLUME` | scalar float | `0.0 ≤ x ≤ 1.0` |
| `MODE` | scalar enum | `full` \| `sound` |

### 4.2 CLI subcommands

Generic:
- `snapback config get KEY` → prints value (unquoted).
- `snapback config set KEY VAL` → validates against table above, calls `config_set`.
- `snapback config show [--json]` → shows all known keys; `--json` outputs a flat object.
- `snapback config path` → prints config file path.

Typed wrappers (convenience, delegate to `config_set`):
- `snapback mode [full|sound]` — already exists; refactor to delegate.
- `snapback volume [0.0–1.0]` — new.
- `snapback browser [name]` — new.
- `snapback focus list` | `add NAME` | `remove NAME` | `set NAME1 NAME2 ...` — new, array-aware.
- `snapback test` — plays notification sound using current config (replaces menu-bar's custom subprocess).

All typed wrappers print the new value after a successful set, for menu-bar readback.

## 5. Menu-bar app changes

### 5.1 `AppState`

- Remove `saveConfig()`. Replace with per-key setters that shell out:
  - `setVolume(Double)` → `snapback volume 0.8`
  - `setMode(String)` → `snapback mode sound`
  - `setBrowser(String)` → `snapback browser "Arc"`
  - `setFocusApps([String])` → `snapback focus set app1 app2 ...`
  - etc.
- Each setter debounces at 200 ms; the latest value wins.
- Keep `loadConfig()` (read path) — no shell round-trip for reads.
- Add `startWatching()` using `DispatchSourceFileSystemObject` on the config file. On `.write | .rename | .delete` events, re-call `loadConfig()` on main queue and publish.
- Remove hardcoded `~/Documents/Programming/AIAttention/notification.mp3` path from `playTestSound`; replace whole function with `ShellCommand.run(snapbackPath + " test")`.

### 5.2 `ShellCommand`

- Add a variadic `run(_ executable: String, args: [String])` that uses `Process.arguments` directly (no shell string concatenation). Keep the existing `run(_ command: String)` for lines that genuinely need a shell.
- Menu-bar mutations must use the argv variant.

### 5.3 Snapback binary resolution

Menu-bar apps don't inherit the user's shell PATH. Resolve on startup:

1. If bundled `Info.plist` key `SnapBackCLIPath` is set → use it.
2. Else check in order: `/usr/local/bin/snapback`, `/opt/homebrew/bin/snapback`, `$HOME/.local/bin/snapback`, `$HOME/.snapback/snapback`.
3. Cache the resolved path in `AppState`. If none found, show a one-line banner in the menu: “CLI not found — reinstall SnapBack".

### 5.4 `FocusAppsView`

- Add up/down chevron buttons per chip. Reorder mutates `appState.focusApps` and calls `setFocusApps`.
- Drag-and-drop reordering is explicitly out of scope.

### 5.5 Browser picker

- Hardcoded list stays but gains Safari in the right position: Chrome, Safari, Arc, Firefox, Brave.
- "Other…" entry is out of scope (custom string would be nice; adds picker complexity).

## 6. Distribution

### 6.1 `.gitignore` additions

```
.DS_Store
SnapBackApp/.build/
SnapBackApp/SnapBack.app/
```

Explicit `git rm --cached` for any currently tracked artifact that matches (verify in F0).

### 6.2 `install.sh`

After config and hooks, new section "Menu-bar app (optional)":

- If `swift --version` succeeds:
  - Ask (respecting `--yes`): "Install menu-bar app? [Y/n]"
  - If yes: `cd SnapBackApp && ./build-app.sh`, then copy `SnapBack.app` to `/Applications/` (sudo only if needed — prefer not to).
  - Print: "Open from /Applications/SnapBack.app or run `snapback app`."
- If Swift is missing: print a one-liner telling the user how to install Xcode Command Line Tools and that `snapback update` will build it later.

Also: replace the end-of-installer `snapback.sh` permissions probe with a quieter probe that only exercises `osascript` System Events access without running the full attention flow.

### 6.3 `snapback update`

After the existing shell-script sync:

- If `/Applications/SnapBack.app` exists:
  - If Swift is available: rebuild from updated sources, copy over the bundle.
  - Else: print warning "Menu-bar app present but Swift not available — skipping rebuild."

### 6.4 `snapback uninstall`

Add: if `/Applications/SnapBack.app` exists, prompt to remove; if confirmed, `rm -rf` (with sudo if needed). Launch-at-login unregistration is skipped — once the bundle is gone, macOS drops the registration at next login anyway.

### 6.5 `snapback status`

Add a "Menu-bar app" section: shows whether `/Applications/SnapBack.app` exists and whether it is currently running.

## 7. Behavior changes

### 7.1 Fast-path sound mode

Keep as-is. Extract the three-line `sysVol`/`effectiveVol`/`afplay` block into a local shell function `_play_notification` inside `snapback.sh` to dedupe. No behavioral change.

### 7.2 Hook installation preserves existing

Refactor `install.sh setup_hooks` to use the same preserving jq expression as `cmd_on`. Any existing hooks from other tools are untouched.

### 7.3 `snapback test` semantics

- Reads current config.
- Plays notification sound at the effective volume.
- Does nothing else (no focus, no state write).

## 8. Version and release

- Bump `VERSION` in `snapback` to `1.2.0`.
- Update help text to list all new commands.
- Update `README.md`:
  - Brief mention of menu-bar app (no screenshot required for this release).
  - `snapback volume`, `snapback focus`, etc. in the commands table.
- Update `ROADMAP.md`: tick "macOS menubar app with on/off toggle" under completed.

## 9. Implementation phases

Each phase is a self-contained commit/series.

### F0 — Stabilize

- Add `.gitignore` entries.
- `git rm --cached` for any accidentally tracked artifacts.
- Commit the currently uncommitted `config.example`/`snapback`/`snapback.sh` changes *as-is* with message "Add VOLUME config and sound-mode fast path".
- Commit the untracked `SnapBackApp/` sources (Package.swift, Sources/, build-app.sh) with message "Add SwiftUI menu-bar app".

Exit criteria: `git status` is clean; no behaviour change.

### F1 — `config_set` foundation

- Implement `config_set` helper in `snapback`.
- Add `snapback config get|set|show|path`.
- Refactor `cmd_mode` to delegate to `config_set`.
- Refactor `install.sh` config write to use `config_set` (`install.sh` will source the functions from `snapback` or inline them — decision during implementation; leaning toward sourcing from a new `snapback-lib.sh`).
- Fix `install.sh setup_hooks` to use preserving jq.
- Replace end-of-installer permission probe with a quiet one.

Tests: set each known key via CLI; edit config by hand; re-set another key; confirm hand-edited key is preserved.

### F2 — Typed CLI wrappers

- Implement `volume`, `browser`, `focus list|add|remove|set`, `test`.
- Update help text and bash completion (if any).

Tests: each new command sets the expected key; invalid inputs are rejected with clear errors.

### F3 — Menu-bar refactor

- Kill `saveConfig`; add per-setter methods that fork-exec `snapback`.
- Add `ShellCommand.run(argv:)` variant.
- Add snapback binary resolution.
- Add config file watcher.
- Remove hardcoded notification.mp3 path; `playTestSound` → `snapback test`.
- Add focus app reorder (chevrons).

Tests: slider debouncing does not drop the final value; external config edit (via CLI) updates UI; test-sound works without the dev path.

### F4 — Distribution

- `install.sh` menu-bar install prompt + build step.
- `snapback update` rebuilds menu-bar app when present.
- `snapback uninstall` offers `/Applications/SnapBack.app` removal.
- `snapback status` reports menu-bar state.

Tests: fresh install on a clean machine (fake via `rm -rf ~/.snapback ~/.config/snapback /Applications/SnapBack.app`); update after a code change; uninstall.

### F5 — Polish

- `VERSION` → 1.2.0.
- README + ROADMAP updates.
- Final `git status` clean, changes pushed as a PR.

## 10. Out of scope

- Homebrew cask, code signing, notarization.
- Windows / Linux support.
- Safari-specific resume (separate roadmap item).
- VLC / Spotify / Apple Music integration (roadmap).
- Drag-and-drop reordering of focus apps (chevrons are enough).
- Arbitrary browser string input (typed wrapper exists; picker covers common cases).
- Rich logging / verbose mode (roadmap).

## 11. Open questions

- Should `snapback-lib.sh` exist (shared bash library sourced by `snapback` and `install.sh`), or should `install.sh` call the installed `snapback config set` to write? The former is self-contained for fresh installs; the latter is simpler but requires `snapback` to be on PATH before it writes config. **Tentative decision:** extract a `snapback-lib.sh` in F1 alongside `config_set`.
- Menu-bar "Other browser…" free-text field: omitted now; revisit if users ask.
- Should `snapback status` surface the effective volume as `VOLUME × system-volume`? Probably yes, small touch.
