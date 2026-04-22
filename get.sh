#!/bin/bash
# SnapBack Remote Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/teoobarca/snapback/main/get.sh | bash
set -euo pipefail

INSTALL_DIR="$HOME/.snapback"
LOCAL_BIN="$HOME/.local/bin"
REPO="teoobarca/snapback"
REPO_URL="https://github.com/$REPO"

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

echo ""
echo -e "${BOLD}SnapBack${NC}"
echo "━━━━━━━━━"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
  print_error "SnapBack requires macOS"
  exit 1
fi

# Download
print_info "Downloading..."

download_tarball() {
  curl -sL "$REPO_URL/archive/main.tar.gz" | tar xz -C "$INSTALL_DIR" --strip-components=1
}

download_git() {
  git clone --depth 1 "$REPO_URL.git" "$INSTALL_DIR" 2>/dev/null
}

# Clean existing installation
if [[ -d "$INSTALL_DIR" ]]; then
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    print_info "Updating existing installation..."
    cd "$INSTALL_DIR"
    if git pull origin main 2>/dev/null; then
      print_success "Updated via git"
    else
      print_warning "Git pull failed, re-downloading..."
      rm -rf "$INSTALL_DIR"
      mkdir -p "$INSTALL_DIR"
      download_tarball
      print_success "Re-downloaded"
    fi
  else
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    download_tarball
    print_success "Downloaded"
  fi
else
  if command -v git &>/dev/null; then
    if download_git; then
      print_success "Downloaded via git"
    else
      mkdir -p "$INSTALL_DIR"
      download_tarball
      print_success "Downloaded"
    fi
  else
    mkdir -p "$INSTALL_DIR"
    download_tarball
    print_success "Downloaded"
  fi
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/snapback" "$INSTALL_DIR/snapback.sh" "$INSTALL_DIR/snapback-resume.sh" "$INSTALL_DIR/install.sh"

# Add to PATH — always use ~/.local/bin (no sudo needed)
print_info "Adding to PATH..."
mkdir -p "$LOCAL_BIN"
ln -sf "$INSTALL_DIR/snapback" "$LOCAL_BIN/snapback"
print_success "Added to $LOCAL_BIN"

# Ensure ~/.local/bin is in PATH for current and future shells
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
  export PATH="$LOCAL_BIN:$PATH"
  # Add to shell profile if not already there
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [[ -f "$rc" ]] && ! grep -q '\.local/bin' "$rc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
      print_info "Added ~/.local/bin to PATH in $(basename "$rc")"
      break
    fi
  done
fi

echo ""
print_success "Installed to $INSTALL_DIR"
echo ""

# Run configuration
exec "$INSTALL_DIR/snapback" install
