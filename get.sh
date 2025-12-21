#!/bin/bash
# SnapBack Remote Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/teoobarca/snapback/main/get.sh | bash
set -euo pipefail

INSTALL_DIR="$HOME/.snapback"
BIN_DIR="/usr/local/bin"
REPO="teoobarca/snapback"
REPO_URL="https://github.com/$REPO"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_info() { echo -e "${BLUE}→${NC} $1"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SnapBack Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
  print_error "SnapBack requires macOS"
  exit 1
fi
print_success "macOS detected"

# Check for existing installation
if [[ -d "$INSTALL_DIR" ]]; then
  print_warning "Existing installation found at $INSTALL_DIR"
  print_info "Updating to latest version..."
  rm -rf "$INSTALL_DIR"
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download: try git first, fallback to tarball
print_info "Downloading SnapBack..."

if command -v git &>/dev/null; then
  if git clone --depth 1 "$REPO_URL.git" "$INSTALL_DIR" 2>/dev/null; then
    print_success "Downloaded via git"
  else
    print_warning "Git clone failed, trying tarball..."
    curl -sL "$REPO_URL/archive/main.tar.gz" | tar xz -C "$INSTALL_DIR" --strip-components=1
    print_success "Downloaded via tarball"
  fi
else
  curl -sL "$REPO_URL/archive/main.tar.gz" | tar xz -C "$INSTALL_DIR" --strip-components=1
  print_success "Downloaded via tarball (git not available)"
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/snapback"
chmod +x "$INSTALL_DIR/snapback.sh"
chmod +x "$INSTALL_DIR/snapback-resume.sh"
chmod +x "$INSTALL_DIR/install.sh"

# Create symlink
print_info "Adding snapback to PATH..."

create_symlink() {
  local target_dir="$1"
  local needs_sudo="$2"

  if [[ "$needs_sudo" == "true" ]]; then
    if sudo ln -sf "$INSTALL_DIR/snapback" "$target_dir/snapback" 2>/dev/null; then
      return 0
    fi
  else
    if ln -sf "$INSTALL_DIR/snapback" "$target_dir/snapback" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

symlink_created=false

# Try /usr/local/bin (with sudo if needed)
if [[ -d "$BIN_DIR" ]]; then
  if [[ -w "$BIN_DIR" ]]; then
    if create_symlink "$BIN_DIR" "false"; then
      print_success "Added to $BIN_DIR"
      symlink_created=true
    fi
  else
    print_info "Requesting sudo access for $BIN_DIR..."
    if create_symlink "$BIN_DIR" "true"; then
      print_success "Added to $BIN_DIR"
      symlink_created=true
    fi
  fi
fi

# Fallback to ~/.local/bin
if [[ "$symlink_created" == "false" ]]; then
  LOCAL_BIN="$HOME/.local/bin"
  mkdir -p "$LOCAL_BIN"
  if create_symlink "$LOCAL_BIN" "false"; then
    print_success "Added to $LOCAL_BIN"
    symlink_created=true

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
      print_warning "$LOCAL_BIN is not in your PATH"
      print_info "Add this to your shell config (~/.zshrc or ~/.bashrc):"
      echo ""
      echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
      echo ""
    fi
  fi
fi

if [[ "$symlink_created" == "false" ]]; then
  print_error "Could not add snapback to PATH"
  print_info "You can run it directly: $INSTALL_DIR/snapback"
fi

echo ""
print_success "SnapBack installed to $INSTALL_DIR"
echo ""

# Run the interactive installer
print_info "Starting configuration..."
echo ""
exec "$INSTALL_DIR/snapback" install
