# SnapBack Distribution Plan

## Current State

- CLI wrapper: `./snapback` with install, status, on/off, uninstall commands
- Manual installation: `git clone` + `./snapback install`
- No global PATH access (user must use `./snapback`)

## Goal

One-liner installation that:
1. Downloads SnapBack to a permanent location
2. Adds `snapback` command to PATH
3. Runs interactive configuration
4. Works without git installed

```bash
curl -fsSL https://raw.githubusercontent.com/teoobarca/snapback/main/get.sh | bash
```

After running, user can use `snapback` from anywhere.

---

## Implementation Plan

### Step 1: Create `get.sh` (remote installer)

Location: `/get.sh` (repo root)

**What it does:**
1. Check for macOS (exit with error on Linux)
2. Create install directory: `~/.snapback/`
3. Download latest release tarball OR clone repo
4. Create symlink: `/usr/local/bin/snapback` → `~/.snapback/snapback`
5. Run `~/.snapback/snapback install`

**Script structure:**
```bash
#!/bin/bash
set -euo pipefail

INSTALL_DIR="$HOME/.snapback"
BIN_DIR="/usr/local/bin"
REPO="teoobarca/snapback"

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "SnapBack requires macOS"
  exit 1
fi

# Create install dir
mkdir -p "$INSTALL_DIR"

# Download (two options):
# Option A: Clone repo (requires git)
# Option B: Download tarball (works without git)

# Create symlink
sudo ln -sf "$INSTALL_DIR/snapback" "$BIN_DIR/snapback"

# Run installer
"$INSTALL_DIR/snapback" install
```

### Step 2: Choose download method

**Option A: Git clone**
```bash
git clone --depth 1 https://github.com/$REPO.git "$INSTALL_DIR"
```
- Pros: Easy updates with `git pull`
- Cons: Requires git

**Option B: Tarball download**
```bash
curl -sL "https://github.com/$REPO/archive/main.tar.gz" | tar xz -C "$INSTALL_DIR" --strip-components=1
```
- Pros: No git required
- Cons: Updates need re-download

**Recommendation:** Try git first, fallback to tarball.

### Step 3: Handle PATH alternatives

Some users may not have write access to `/usr/local/bin`. Alternatives:

1. `/usr/local/bin` (default, may need sudo)
2. `~/.local/bin` (user-local, needs PATH setup)
3. Add to shell rc file (`export PATH="$HOME/.snapback:$PATH"`)

**Recommendation:** Try `/usr/local/bin` with sudo, explain if it fails.

### Step 4: Add update command

Add to `snapback` CLI:
```bash
snapback update   # Pull latest version
```

Implementation:
```bash
cmd_update() {
  cd "$SCRIPT_DIR"
  if [[ -d ".git" ]]; then
    git pull origin main
  else
    # Re-download tarball
    curl -sL "https://github.com/$REPO/archive/main.tar.gz" | tar xz --strip-components=1
  fi
  print_success "Updated to latest version"
}
```

### Step 5: Add uninstall to get.sh

The `snapback uninstall` should also:
- Remove `~/.snapback/` directory
- Remove `/usr/local/bin/snapback` symlink

---

## File Changes Summary

| File | Action |
|------|--------|
| `get.sh` | CREATE - Remote installer script |
| `snapback` | UPDATE - Add `update` command |
| `snapback` | UPDATE - Improve `uninstall` to remove global install |
| `README.md` | UPDATE - Change installation instructions |

---

## New Installation Flow

```
User runs:
  curl -fsSL https://raw.githubusercontent.com/teoobarca/snapback/main/get.sh | bash

Script does:
  1. Check macOS ✓
  2. Download to ~/.snapback/ ✓
  3. Symlink to /usr/local/bin/snapback ✓
  4. Run snapback install ✓
     - Configure apps/browser
     - Setup Claude hooks
     - Grant permissions

User can now:
  snapback status
  snapback on/off
  snapback update
  snapback uninstall
```

---

## Testing Checklist

- [ ] Fresh install works
- [ ] Install over existing works (updates)
- [ ] Works without git installed
- [ ] Works without sudo (fallback to ~/.local/bin)
- [ ] `snapback update` works
- [ ] `snapback uninstall` removes everything
- [ ] Symlink points correctly after update

---

## Future Improvements

1. **Version pinning**: `curl ... | bash -s -- --version 1.0.0`
2. **Checksum verification**: Verify download integrity
3. **Rollback**: Keep previous version for rollback
4. **Auto-update**: Check for updates periodically
