#!/bin/bash
# SnapBack Installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/snapback"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

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

  # Create config
  mkdir -p "$CONFIG_DIR"

  focus_apps_str="("
  for app in "${FOCUS_APPS_ARR[@]}"; do
    app=$(echo "$app" | xargs)
    focus_apps_str+="\"$app\" "
  done
  focus_apps_str="${focus_apps_str% })"

  cat > "$CONFIG_DIR/config" <<EOF
# SnapBack Configuration
FOCUS_APPS=$focus_apps_str
FOCUS_DELAY=$focus_delay
BROWSER="$browser"
SEEK_BACK_SECONDS=$seek_back
THROTTLE_SECONDS=$throttle
NOTIFICATION_SOUND="$notification_sound"
EOF

  echo ""
  print_success "Config saved to $CONFIG_DIR/config"
  print_info "Edit this file for advanced settings (delays, sounds, etc.)"
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

  if [[ -f "$CLAUDE_SETTINGS" ]]; then
    tmp=$(mktemp)
    jq --arg snapback "$SCRIPT_DIR/snapback.sh" --arg resume "$SCRIPT_DIR/snapback-resume.sh" '
      .hooks.PermissionRequest = [{matcher: "*", hooks: [{type: "command", command: $snapback}]}] |
      .hooks.Stop = [{hooks: [{type: "command", command: $snapback}]}] |
      .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(.matcher != "Edit|Write|Bash"))) + [{matcher: "Edit|Write|Bash", hooks: [{type: "command", command: $resume}]}] |
      .hooks.UserPromptSubmit = [{hooks: [{type: "command", command: $resume}]}]
    ' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
  else
    jq -n --arg snapback "$SCRIPT_DIR/snapback.sh" --arg resume "$SCRIPT_DIR/snapback-resume.sh" '{
      hooks: {
        PermissionRequest: [{matcher: "*", hooks: [{type: "command", command: $snapback}]}],
        Stop: [{hooks: [{type: "command", command: $snapback}]}],
        PostToolUse: [{matcher: "Edit|Write|Bash", hooks: [{type: "command", command: $resume}]}],
        UserPromptSubmit: [{hooks: [{type: "command", command: $resume}]}]
      }
    }' > "$CLAUDE_SETTINGS"
  fi
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

# Source config to get BROWSER
[[ -f "$CONFIG_DIR/config" ]] && source "$CONFIG_DIR/config"

if "$SCRIPT_DIR/snapback.sh" 2>/dev/null; then
  print_success "Permissions OK"
else
  print_warning "You may need to grant permissions in System Settings → Privacy & Security"
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
