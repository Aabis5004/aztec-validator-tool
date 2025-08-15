#!/bin/bash
# Aztec Validator Tool - One-Click Installer (WSL/Linux/macOS)
# Author: Aabis Lone

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
info(){ echo -e "${BLUE}ℹ${NC} $*"; }
ok(){ echo -e "${GREEN}✓${NC} $*"; }
err(){ echo -e "${RED}✗${NC} $*"; }
warn(){ echo -e "${YELLOW}⚠${NC} $*"; }

detect_os() {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then OS="wsl"; else OS="linux"; fi
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
  else
    OS="unknown"
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

install_deps() {
  local missing=()
  for c in curl jq bc timeout; do need_cmd "$c" || missing+=("$c"); done

  if ((${#missing[@]})); then
    warn "Installing missing dependencies: ${missing[*]}"
    case "$OS" in
      wsl|linux)
        info "Updating package list..."
        sudo apt update
        # timeout is in coreutils; most systems have it
        sudo apt install -y curl jq bc coreutils ca-certificates
        sudo update-ca-certificates || true
        ;;
      mac)
        if need_cmd brew; then
          brew install curl jq bc coreutils
        else
          err "Homebrew not found. Install from https://brew.sh"
          exit 1
        fi
        ;;
      *)
        err "Unsupported OS: $OSTYPE"
        exit 1
        ;;
    esac
    ok "Dependencies installed."
  else
    ok "All dependencies already installed!"
  fi
}

main() {
  clear
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║            AZTEC VALIDATOR TOOL INSTALLER                   ║"
  echo "║                       One-Click Setup                       ║"
  echo "║                       by Aabis Lone                         ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo

  detect_os
  info "Detected OS: ${OS}"

  info "Checking dependencies..."
  install_deps
  echo

  # ---- Settings ----
  local INSTALL_DIR="$HOME/aztec-validator-tool"
  local REPO="Aabis5004/aztec-validator-tool"
  local RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
  local SCRIPT_FILE="validator-stats.sh"
  local WRAPPER_DIR="$HOME/.local/bin"
  local WRAPPER="$WRAPPER_DIR/aztec-stats"
  # ------------------

  info "Creating installation directory: $INSTALL_DIR"
  if [[ -d "$INSTALL_DIR" ]]; then
    warn "Found existing installation. Updating..."
    rm -rf "$INSTALL_DIR"
  fi
  mkdir -p "$INSTALL_DIR"

  info "Downloading validator stats script..."
  info "URL: ${RAW_BASE}/${SCRIPT_FILE}"
  if ! curl -fSL "${RAW_BASE}/${SCRIPT_FILE}" -o "${INSTALL_DIR}/${SCRIPT_FILE}"; then
    err "Failed to download script from GitHub"
    echo "Please check:"
    echo "  • Internet connection"
    echo "  • Repo is public"
    echo "  • File exists at: ${RAW_BASE}/${SCRIPT_FILE}"
    exit 1
  fi
  chmod +x "${INSTALL_DIR}/${SCRIPT_FILE}"

  info "Installing wrapper command: aztec-stats"
  mkdir -p "$WRAPPER_DIR"
  cat > "$WRAPPER" <<EOF
#!/bin/bash
exec "$INSTALL_DIR/$SCRIPT_FILE" "\$@"
EOF
  chmod +x "$WRAPPER"

  # Ensure ~/.local/bin is on PATH for current shell (no .bashrc edits needed)
  if [[ ":$PATH:" != *":$WRAPPER_DIR:"* ]]; then
    warn "~/.local/bin is not on PATH for this session."
    echo "You can run with full path: $WRAPPER"
    echo "Or add to PATH temporarily: export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo "Or restart your terminal."
  fi

  ok "Installation complete!"
  echo
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                       HOW TO USE                            ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo
  echo "📍 Installation path: $INSTALL_DIR"
  echo
  echo "🎯 Method 1 - Global command:"
  echo "   aztec-stats <validator_address>"
  echo
  echo "🎯 Method 2 - Direct:"
  echo "   $INSTALL_DIR/$SCRIPT_FILE <validator_address>"
  echo
  echo "📝 Example:"
  echo "   aztec-stats 0x581f8afba0ba7aa93c662e730559b63479ba70e3"
  echo
  echo "🆘 Repo: https://github.com/$REPO"
  echo
}

main "$@"
