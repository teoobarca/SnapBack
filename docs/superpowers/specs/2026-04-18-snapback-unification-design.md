# SnapBack Unification — Design

Date: 2026-04-18
Status: Reviewed (code-reviewer + second opinion) — awaiting user approval
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

Shell function inside `snapback-lib.sh` (sourced by `snapback` and `install.sh`). Contract:

- **Rewriter is awk, not sed.** `sed 's/^KEY=.*/KEY="VALUE"/'` breaks on values containing `/`, `&`, `\`, or newlines. `config_set` uses a bash read-loop that matches `^KEY=` prefix and substitutes the whole line with a pre-built replacement; the replacement string is constructed in bash (no interpreter hops), so no metacharacter escaping is needed at substitution time.
- **Shell-safe value escaping.** Values may contain any byte except `NUL` and newline (newlines are rejected at validation). Before writing, the value is wrapped in double quotes and the four bytes `\`, `$`, `` ` ``, `"` are backslash-escaped. This round-trips correctly under `source` (which is how runtime scripts read the config) and survives `grep`/`sed` consumers that happen to run over the file. Example: `NOTIFICATION_SOUND=/Users/a/b.mp3` is written as `NOTIFICATION_SOUND="/Users/a/b.mp3"`; `NOTIFICATION_SOUND=$HOME/x.mp3` is rejected (validator does not expand; user must pass the resolved path).
- **Scalar keys** (default): if the key exists, replace its line in place; otherwise append `KEY="VALUE"` with a preceding comment (`# Added by snapback config set`).
- **Array keys** (set: `FOCUS_APPS`): `config_set` is called with a pre-formatted bash-array literal in its second argument (e.g., `("Cursor" "Ghostty")`). The typed CLI wrapper `snapback focus set` builds this literal from argv and escapes each token with the same rule above. The writer substitutes the line matching `^FOCUS_APPS=` with `FOCUS_APPS=<value>` verbatim.
- **Atomic and locked.** `flock -x` on a sibling lockfile (`~/.config/snapback/.config.lock`) for the duration of read→rewrite→rename. Write goes to `config.tmp.$$`, then `mv` into place. Concurrent `config_set` calls from CLI + menu-bar cannot race.
- **Preserve** comments, blank lines, unknown keys, line order.
- **Validate**: reject unknown keys unless `--allow-new` is passed; values per table below; values containing literal NL or NUL rejected.

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
- **`loadConfig()` completeness.** Currently it does not read `FOCUS_DELAY` or `NOTIFICATION_SOUND`; add both. Harden `parseFocusApps` for the exact grammar `config_set` produces (double-quoted tokens with `\`, `$`, `` ` ``, `"` backslash-escaped). Parser is unit-tested against the set of values the writer can produce — no attempt to handle arbitrary bash.
- **File watcher with echo suppression.** Add `startWatching()` using `DispatchSourceFileSystemObject` on the config file (also re-arming on `.rename`/`.delete` since atomic writes replace the inode). Maintain `lastOutgoingWriteAt: Date?`; every setter updates it immediately before `Process.run`. The watcher callback ignores events whose timestamp is within 500 ms of `lastOutgoingWriteAt`. This prevents slider feedback loops without dropping legitimate external edits (CLI `snapback config set` still produces an event that, while within the suppression window if the user is driving it from another terminal, will be re-read on the next change).
- Remove hardcoded `~/Documents/Programming/AIAttention/notification.mp3` path from `playTestSound`; replace whole function with `ShellCommand.run(executable: snapbackPath, args: ["test"])`.

### 5.2 `ShellCommand`

- Add `run(executable: String, args: [String]) -> (stdout: String, stderr: String, exitCode: Int32)`. Uses `Process.arguments` directly (no shell concatenation). Existing call-sites that need a shell stay on a renamed `runShell(_:)` variant, but must pass no user-controlled input.
- **PATH augmentation.** When spawned from Finder / LaunchAgent, `ProcessInfo.processInfo.environment["PATH"]` is macOS's short default (`/usr/bin:/bin:/usr/sbin:/sbin`, plus `/usr/local/bin` on newer systems). `snapback` itself calls `jq`; if `jq` is in `/opt/homebrew/bin`, it will fail. Every `Process` started from the app sets `environment` to a shallow-copy of `ProcessInfo`'s with `PATH` prefixed by `/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin`.
- **Exit code surface.** `AppState` setters consume the exit code; non-zero → show a transient error banner in the menu view (one-liner at the top, auto-dismisses on next successful op). Errors never throw; they set an `@Published var lastError: String?`.

### 5.3 Snapback binary resolution

Menu-bar apps don't inherit the user's shell PATH. Resolve on startup:

1. If bundled `Info.plist` key `SnapBackCLIPath` is set → use it. (`build-app.sh` writes this at build time based on the install layout.)
2. Else check in order: `/usr/local/bin/snapback`, `/opt/homebrew/bin/snapback`, `$HOME/.local/bin/snapback`, `$HOME/.snapback/snapback`.
3. Resolve symlinks with `realpath` so relative working directories are unambiguous.
4. Cache the resolved path in `AppState`. If none found, set `lastError = "SnapBack CLI not found — reinstall SnapBack"` and disable mutation controls in the UI.

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

- **Tarball branch fix.** Current `cmd_update` tarball branch copies only `snapback`, `snapback.sh`, `snapback-resume.sh`, `install.sh`. It must also rsync `SnapBackApp/` sources into the install directory so the menu-bar app can be (re)built. Git branch is unchanged (pulls everything).
- **Rebuild logic.**
  - If `/Applications/SnapBack.app` exists and Swift is available → rebuild + copy.
  - If `/Applications/SnapBack.app` is absent and Swift is available → ask "Install menu-bar app now? [y/N]" (prompt respects existing `-y` / non-TTY behavior). This fixes the "declined at install, no path forward" issue.
  - If Swift is unavailable → print a one-liner on how to install Command Line Tools; do not fail.

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

Each phase is a self-contained commit / small commit series. Tests live in `tests/` and use [bats-core](https://github.com/bats-core/bats-core) for shell coverage (`brew install bats-core` locally; phase F1 introduces it). Swift changes are verified manually — the menu-bar app is too thin to justify a Swift test harness today.

### F0a — Repo hygiene + checkpoint existing CLI work

- Add `.gitignore` entries (see §6.1).
- `git rm --cached` any accidentally tracked artifacts.
- Commit the currently uncommitted `config.example`/`snapback`/`snapback.sh` changes *as-is* with message **"Add VOLUME config and sound-mode fast path"**.

Exit criteria: `git status` clean w.r.t. shell scripts; `SnapBackApp/` still untracked; no behaviour change.

### F0b — Commit menu-bar sources with `saveConfig` defanged

Committing `AppState.saveConfig()` as-is ships an active destructive writer (loses hand-edited `FOCUS_DELAY`, `NOTIFICATION_SOUND`) before F3 lands. To avoid that window:

- Commit `SnapBackApp/` sources (Package.swift, Sources/, build-app.sh).
- **In the same commit**, stub `saveConfig()` to `print("saveConfig: no-op until F3 lands")` and disable mutating UI controls (`.disabled(true)`) in `MenuBarView` and `FocusAppsView`. The app still launches and shows current config (read-only).
- Commit message: **"Add SwiftUI menu-bar app (read-only pending F3)"**.

This keeps the repo honest without committing known-broken writes.

### F1 — `snapback-lib.sh` + `config_set` foundation

- Create `snapback-lib.sh` with `config_set`, `config_get`, known-keys table, validators, flock helper.
- Source it from `snapback` (search order: `$SCRIPT_DIR/snapback-lib.sh` → `/usr/local/share/snapback/snapback-lib.sh`).
- Source it from `install.sh` likewise.
- Add `snapback config get|set|show|path`.
- Refactor `cmd_mode` to delegate to `config_set`.
- Refactor `install.sh` config writer to use `config_set` (+ migration: on existing config, set defaults for any missing known key via `config_set --allow-new`).
- **Hotfix-style:** fix `install.sh setup_hooks` to use preserving jq (same filter as `cmd_on`) so users don't lose other hooks on reconfigure. This could be cherry-picked ahead of F1 if needed.
- Replace end-of-installer permission probe with a quiet one (bare `osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'`).
- Tests: `tests/config_set.bats` covering: preserve unknown keys, append missing keys, reject newline values, escape `\`/`$`/`` ` ``/`"` correctly, array rewrite for `FOCUS_APPS`, concurrent writes under `flock` don't corrupt.

### F2 — Typed CLI wrappers

- Implement `volume`, `browser`, `focus list|add|remove|set`, `test`.
- Update help text.
- `snapback test` reads config, plays notification at effective volume, no side effects.
- Tests: `tests/cli_typed.bats` for input validation and round-tripping with `config get`.

### F3 — Menu-bar refactor (and re-enabling writes)

**Blocked on F2** (menu-bar depends on typed CLI wrappers existing).

- Delete `saveConfig()` stub from F0b. Add per-key setters (`setVolume`, `setMode`, `setBrowser`, `setFocusApps`, `setThrottleSeconds`, `setSeekBackSeconds`).
- Debounce 200 ms per key, latest-wins.
- Add `ShellCommand.run(executable:args:) → (stdout, stderr, exitCode)` with PATH augmentation; add error-banner UX via `@Published lastError`.
- Add snapback binary resolution (§5.3).
- Extend `loadConfig()` to read `FOCUS_DELAY` and `NOTIFICATION_SOUND`.
- Harden `parseFocusApps` for writer's escaping grammar.
- Add `DispatchSourceFileSystemObject` watcher with 500 ms echo suppression.
- Replace `playTestSound` with `snapback test`.
- Re-enable mutating controls (remove `.disabled(true)`).
- Add focus app reorder (up/down chevrons).
- Tests: manual acceptance checklist in PR description (slider settles without drops; CLI edit reflected in UI within 1 s; test-sound works on a fresh machine).

### F4 — Distribution + polish

- `install.sh` menu-bar install prompt + build step (§6.2).
- `snapback update` tarball branch copies `SnapBackApp/`; rebuild logic per §6.3.
- `snapback uninstall` offers `/Applications/SnapBack.app` removal.
- `snapback status` reports menu-bar state and effective volume.
- `VERSION` → 1.2.0; update help text listing.
- README: mention menu-bar app and new commands.
- ROADMAP: tick "macOS menubar app with on/off toggle" under completed.
- Tests: manual fresh-install + update + uninstall on a throwaway user (scripted as `tests/integration_install.sh` that operates on `$HOME` set to a tmpdir — best-effort, not CI).

## 10. Out of scope

- Homebrew cask, code signing, notarization. (Locally built `.app`s escape Gatekeeper quarantine; distribution of a pre-built artifact would need this — not today.)
- Windows / Linux support.
- Safari-specific resume (separate roadmap item).
- VLC / Spotify / Apple Music integration (roadmap).
- Drag-and-drop reordering of focus apps (chevrons are enough).
- Arbitrary browser string input (typed wrapper exists; picker covers common cases).
- Rich logging / verbose mode (roadmap).
- Swift-side test harness (menu-bar is thin; all critical logic lives in bash and is covered by bats).

### Documented platform requirements

- macOS 13+ (menu-bar app `LSMinimumSystemVersion=13.0`, `Package.swift` platforms `.macOS(.v13)`).
- Swift 5.9+ toolchain for building the menu-bar app (installed via Xcode or `xcode-select --install`).
- CLI-only usage works on older macOS versions that can run bash + osascript.

## 11. Open questions

*(all resolved during review; kept here for audit trail)*

- **`snapback-lib.sh` as a shared bash library?** Yes. F1 introduces it, sourced by both `snapback` and `install.sh`. Simpler than calling the installed `snapback config set` from the installer, which would have a chicken-and-egg during first install.
- **Menu-bar "Other browser…" free-text field:** out of scope for 1.2.0. Revisit if users ask.
- **Should `snapback status` surface effective volume (`VOLUME × system-volume`)?** Yes. Small touch, added in F4.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| `install.sh` hooks clobbering user's other hooks | F1 fixes; cherry-pickable hotfix ahead of F1 if a user reports it |
| `saveConfig` destructiveness shipping between F0b and F3 | F0b stubs `saveConfig` to no-op + disables mutating UI |
| Concurrent writes racing on config file | `flock` in `config_set` |
| File-watcher feedback loop in menu-bar | 500 ms echo-suppression window tied to `lastOutgoingWriteAt` |
| Menu-bar launched from Finder has no `$PATH` | Hardcoded CLI search list + explicit `PATH` prepend on subprocess |
| `snapback update` via tarball doesn't include `SnapBackApp/` | F4 adds sources to tarball copy |
| Users who declined menu-bar at install have no upgrade path | F4: `snapback update` offers install when Swift is present |
| Existing configs missing new keys after upgrade | F1 migration: `config_set --allow-new` fills missing known keys on install run |
| `sed` metacharacters in user values | Awk/bash read-loop writer, no sed substitution |
