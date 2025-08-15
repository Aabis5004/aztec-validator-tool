#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
info(){ echo -e "${BLUE}ℹ${NC} $*"; }
ok(){ echo -e "${GREEN}✓${NC} $*"; }
warn(){ echo -e "${YELLOW}⚠${NC} $*"; }
err(){ echo -e "${RED}✗${NC} $*"; }

detect_os() {
  if [[ "${OSTYPE:-}" == linux-gnu* ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then OS="wsl"; else OS="linux"; fi
  elif [[ "${OSTYPE:-}" == darwin* ]]; then OS="mac"; else OS="unknown"; fi
}

install_deps() {
  local missing=()
  for b in curl jq bc; do command -v "$b" >/dev/null 2>&1 || missing+=("$b"); done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  warn "Installing dependencies: ${missing[*]}"
  case "${OS}" in
    wsl|linux) sudo apt update && sudo apt install -y "${missing[@]}" ;;
    mac) command -v brew >/dev/null || { err "Install Homebrew: https://brew.sh"; exit 1; }; brew install "${missing[@]}" ;;
    *) err "Unsupported OS: ${OSTYPE:-unknown}"; exit 1 ;;
  esac
  ok "Dependencies installed"
}

main() {
  clear || true
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║            AZTEC VALIDATOR TOOL INSTALLER                   ║"
  echo "║                   One-Click Setup                           ║"
  echo "║                   by Aabis Lone                             ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  detect_os
  info "Detected OS: ${OS}"
  info "Checking dependencies…"
  install_deps
  echo ""

  INSTALL_DIR="${HOME}/aztec-validator-tool"
  info "Creating installation directory: $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"

  info "Downloading validator stats script…"
  GITHUB_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main/validator-stats.sh"
  curl -sSfL "$GITHUB_URL" -o validator-stats.sh || { err "Download failed"; exit 1; }
  chmod +x validator-stats.sh

  # Global wrapper
  mkdir -p "${HOME}/.local/bin"
  cat > "${HOME}/.local/bin/aztec-stats" <<'EOF'
#!/usr/bin/env bash
exec "$HOME/aztec-validator-tool/validator-stats.sh" "$@"
EOF
  chmod +x "${HOME}/.local/bin/aztec-stats"

  # Ensure PATH
  if ! grep -q '\.local/bin' "${HOME}/.bashrc" 2>/dev/null; then
    {
      echo ""
      echo "# Aztec Validator Tool"
      echo 'export PATH="$HOME/.local/bin:$PATH"'
    } >> "${HOME}/.bashrc"
    info "Added ~/.local/bin to PATH. Run: source ~/.bashrc"
  fi

  ok "Installation complete!"
  echo ""
  echo "How to run:"
  echo "  aztec-stats 0xYOUR_ADDRESS --epochs 1797:1897"
  echo "  aztec-stats 0xYOUR_ADDRESS --last 120 --set-cookie"
  echo ""
  echo "If Cloudflare blocks requests, set your cookie once:"
  echo "  aztec-stats 0xYOUR_ADDRESS --set-cookie"
}

main "$@"
