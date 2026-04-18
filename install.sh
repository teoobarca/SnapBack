#!/bin/bash
# SnapBack Installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/snapback"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

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
AUTO_YES=false
for arg in "$@"; do
  case "$arg" in
    -y|--yes) AUTO_YES=true ;;
  esac
done

# Use /dev/tty for interactive input (works with curl | bash)
if [[ -t 0 ]]; then
  TTY_INPUT="/dev/stdin"
else
  TTY_INPUT="/dev/tty"
fi

# Helper for prompts with defaults
ask() {
  local prompt="$1"
  local default="$2"
  local var_name="$3"

  if [[ "$AUTO_YES" == "true" ]]; then
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
# CONFIGURATION
# ============================================================

if [[ -f "$CONFIG_DIR/config" ]]; then
  print_success "Config found: $CONFIG_DIR/config"
  source "$CONFIG_DIR/config"

  if [[ "$AUTO_YES" == "false" ]]; then
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
  echo ""
  print_info "Quick setup (press Enter for defaults)"
  echo ""

  # Only ask essential questions
  echo -e "${BOLD}Focus apps${NC} - which apps to activate when Claude needs attention"
  echo "Comma-separated, last one stays on top"
  ask "[Cursor,Ghostty]: " "Cursor,Ghostty" focus_apps_input
  IFS=',' read -ra FOCUS_APPS_ARR <<< "$focus_apps_input"

  echo ""
  echo -e "${BOLD}Browser${NC} - for pausing/resuming media"
  ask "[Google Chrome]: " "Google Chrome" browser

  # Use smart defaults for the rest
  focus_delay="0.5"
  seek_back="1"
  throttle="2"
  notification_sound="default"

  # Create config using config_set
  mkdir -p "$CONFIG_DIR"
  : > "$CONFIG_DIR/config"

  # Build FOCUS_APPS bash-array literal
  focus_apps_literal='('
  for app in "${FOCUS_APPS_ARR[@]}"; do
    app="$(echo "$app" | xargs)"  # trim whitespace
    # Escape the same way config_set does (backslash, dollar, backtick, dquote)
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
  print_info "Edit this file for advanced settings (delays, sounds, etc.)"
fi

# Migrate: ensure all known keys exist in an existing config.
if [[ "$skip_config" == "true" ]]; then
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

if setup_hooks; then
  print_success "Claude Code hooks configured"
else
  print_warning "Hooks not configured - run 'snapback on' after installing jq"
fi

# ============================================================
# PERMISSIONS
# ============================================================

echo ""
print_info "Testing macOS permissions..."

# Quiet probe: just try System Events access. No app focus, no sound, no state.
if osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' &>/dev/null; then
  print_success "Permissions OK"
else
  print_warning "Grant permission: System Settings → Privacy & Security → Automation → Terminal/iTerm → System Events"
fi

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
