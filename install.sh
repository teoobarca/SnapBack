#!/bin/bash
# SnapBack Installer — zero sudo, zero prompts by default.
# Use --interactive for guided setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/snapback"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
APP_DIR="$HOME/Applications"

# Load shared config library
if [[ -f "$SCRIPT_DIR/snapback-lib.sh" ]]; then
  source "$SCRIPT_DIR/snapback-lib.sh"
else
  echo "error: snapback-lib.sh not found next to install.sh" >&2
  exit 1
fi
SNAPBACK_CONFIG_FILE="$CONFIG_DIR/config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_info() { echo -e "${BLUE}→${NC} $1"; }

# Parse arguments
INTERACTIVE=false
for arg in "$@"; do
  case "$arg" in
    -i|--interactive) INTERACTIVE=true ;;
    -y|--yes) ;;  # legacy flag, same as default (non-interactive)
  esac
done

# Use /dev/tty for interactive input (works with curl | bash)
if [[ -t 0 ]]; then
  TTY_INPUT="/dev/stdin"
else
  TTY_INPUT="/dev/tty"
fi

ask() {
  local prompt="$1"
  local default="$2"
  local var_name="$3"

  if [[ "$INTERACTIVE" != "true" ]]; then
    eval "$var_name=\"$default\""
    return
  fi

  read -p "$prompt" response < "$TTY_INPUT"
  eval "$var_name=\"\${response:-$default}\""
}

echo ""
echo -e "${BOLD}SnapBack Installer${NC}"
echo "━━━━━━━━━━━━━━━━━━━"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
  print_error "SnapBack requires macOS"
  exit 1
fi

# ============================================================
# DEPENDENCIES
# ============================================================

# jq — required for hook installation
if ! command -v jq &>/dev/null; then
  if command -v brew &>/dev/null; then
    print_info "Installing jq..."
    brew install jq 2>/dev/null && print_success "Installed jq" || print_warning "Failed to install jq via brew"
  else
    print_warning "jq not found — install with: brew install jq"
    print_info "Hooks will be configured when jq is available (run: snapback on)"
  fi
fi

# ============================================================
# CONFIGURATION
# ============================================================

if [[ -f "$CONFIG_DIR/config" ]]; then
  print_success "Config found: $CONFIG_DIR/config"
  source "$CONFIG_DIR/config"

  if [[ "$INTERACTIVE" == "true" ]]; then
    echo ""
    echo "  1) Keep current config"
    echo "  2) Reconfigure"
    ask "Choose [1]: " "1" config_choice

    if [[ "$config_choice" != "2" ]]; then
      skip_config=true
    else
      skip_config=false
    fi
  else
    skip_config=true
  fi
else
  skip_config=false
fi

if [[ "$skip_config" == "false" ]]; then
  if [[ "$INTERACTIVE" == "true" ]]; then
    echo ""
    print_info "Quick setup (press Enter for defaults)"
    echo ""

    echo -e "${BOLD}Focus apps${NC} - which apps to activate when Claude needs attention"
    echo "Comma-separated, last one stays on top"
    ask "[Cursor,Ghostty]: " "Cursor,Ghostty" focus_apps_input

    echo ""
    echo -e "${BOLD}Browser${NC} - for pausing/resuming media"
    ask "[Google Chrome]: " "Google Chrome" browser
  else
    # Smart defaults — detect what's actually installed
    focus_apps_input=""
    for app in Cursor "Visual Studio Code" Zed; do
      if [[ -d "/Applications/$app.app" ]] || [[ -d "$HOME/Applications/$app.app" ]]; then
        focus_apps_input="$app"
        break
      fi
    done
    [[ -z "$focus_apps_input" ]] && focus_apps_input="Cursor"

    # Detect terminal
    local_terminal=""
    for term in Ghostty iTerm2 "Terminal"; do
      if [[ -d "/Applications/$term.app" ]] || [[ -d "$HOME/Applications/$term.app" ]] || [[ -d "/System/Applications/Utilities/$term.app" ]]; then
        local_terminal="$term"
        break
      fi
    done
    [[ -n "$local_terminal" ]] && focus_apps_input="$focus_apps_input,$local_terminal"

    # Detect browser
    browser=""
    for b in "Google Chrome" Arc Brave "Microsoft Edge"; do
      if [[ -d "/Applications/$b.app" ]]; then
        browser="$b"
        break
      fi
    done
    [[ -z "$browser" ]] && browser="Google Chrome"

    print_info "Auto-detected: focus=$focus_apps_input, browser=$browser"
  fi

  IFS=',' read -ra FOCUS_APPS_ARR <<< "$focus_apps_input"

  focus_delay="0.5"
  seek_back="1"
  throttle="2"
  notification_sound="default"

  mkdir -p "$CONFIG_DIR"
  : > "$CONFIG_DIR/config"

  focus_apps_literal='('
  for app in "${FOCUS_APPS_ARR[@]}"; do
    app="$(echo "$app" | xargs)"
    esc="${app//\\/\\\\}"
    esc="${esc//\$/\\\$}"
    esc="${esc//\`/\\\`}"
    esc="${esc//\"/\\\"}"
    focus_apps_literal+="\"$esc\" "
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

  echo ""
  print_success "Config saved to $CONFIG_DIR/config"
fi

# Migrate: ensure all known keys exist with sensible defaults.
if [[ "$skip_config" == "true" ]]; then
  config_get FOCUS_APPS >/dev/null || config_set FOCUS_APPS '("Cursor" "Ghostty")' --allow-new
  config_get FOCUS_DELAY >/dev/null || config_set FOCUS_DELAY "0.5" --allow-new
  config_get BROWSER >/dev/null || config_set BROWSER "Google Chrome" --allow-new
  config_get SEEK_BACK_SECONDS >/dev/null || config_set SEEK_BACK_SECONDS "1" --allow-new
  config_get THROTTLE_SECONDS >/dev/null || config_set THROTTLE_SECONDS "2" --allow-new
  config_get NOTIFICATION_SOUND >/dev/null || config_set NOTIFICATION_SOUND "default" --allow-new
  config_get VOLUME >/dev/null || config_set VOLUME "1.0" --allow-new
  config_get MODE >/dev/null || config_set MODE "full" --allow-new
fi

# ============================================================
# SCRIPTS
# ============================================================

chmod +x "$SCRIPT_DIR/snapback.sh" "$SCRIPT_DIR/snapback-resume.sh" 2>/dev/null || true

# ============================================================
# CLAUDE CODE HOOKS
# ============================================================

echo ""
print_info "Setting up Claude Code hooks..."

setup_hooks() {
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

  if ! command -v jq &>/dev/null; then
    print_warning "jq not found — hooks not configured"
    print_info "Install jq, then run: snapback on"
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

if setup_hooks; then
  print_success "Claude Code hooks configured"
else
  print_warning "Hooks not configured — run 'snapback on' after installing jq"
fi

# ============================================================
# PERMISSIONS
# ============================================================

echo ""
print_info "Testing macOS permissions..."

if osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' &>/dev/null; then
  print_success "Permissions OK"
else
  print_warning "Grant permission: System Settings > Privacy & Security > Automation > Terminal > System Events"
fi

# ============================================================
# POKE HELPER
# ============================================================

if [[ -d "$SCRIPT_DIR/poke" ]]; then
  if command -v make >/dev/null 2>&1 && command -v clang >/dev/null 2>&1; then
    ( cd "$SCRIPT_DIR/poke" && make -s ) || {
      echo "warning: snapback-poke failed to build; bridge feature will use fallback" >&2
    }
    # Install to ~/.local/bin (no sudo)
    if [[ -x "$SCRIPT_DIR/poke/build/snapback-poke" ]]; then
      mkdir -p "$HOME/.local/bin"
      ln -sf "$SCRIPT_DIR/poke/build/snapback-poke" "$HOME/.local/bin/snapback-poke"
    fi
  fi
fi

# ============================================================
# MENU-BAR APP (automatic if Swift is available)
# ============================================================
echo ""
if command -v swift &>/dev/null && [[ -d "$SCRIPT_DIR/SnapBackApp" ]]; then
  if [[ "$INTERACTIVE" == "true" ]]; then
    ask "Build & install SnapBack menu-bar app? [Y/n]: " "Y" install_app
  else
    install_app="Y"
  fi

  case "$install_app" in
    [Yy]*)
      print_info "Building menu-bar app (this may take a minute)..."
      (
        cd "$SCRIPT_DIR/SnapBackApp"
        export SNAPBACK_CLI_PATH="$HOME/.local/bin/snapback"
        ./build-app.sh
      )
      # Install to ~/Applications (no sudo)
      mkdir -p "$APP_DIR"
      rm -rf "$APP_DIR/SnapBack.app"
      cp -R "$SCRIPT_DIR/SnapBackApp/SnapBack.app" "$APP_DIR/"
      print_success "Installed to ~/Applications/SnapBack.app"
      ;;
    *)
      print_info "Skipped. Re-run 'snapback update' any time to install."
      ;;
  esac
else
  if ! command -v swift &>/dev/null; then
    print_info "Menu-bar app skipped (Swift not available)"
    print_info "Install Xcode Command Line Tools: xcode-select --install"
  fi
fi

# ============================================================
# DONE
# ============================================================

echo ""
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo "  Config:   $CONFIG_DIR/config"
echo "  Commands: snapback status | on | off | update"
echo ""
print_info "Restart Claude Code to activate hooks"
echo ""
