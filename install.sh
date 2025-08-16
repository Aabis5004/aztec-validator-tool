#!/usr/bin/env bash
# Enhanced Aztec Validator Tool Installer
# Author: Aabis Lone
# Cross-platform installer with proper directory handling

set -Eeuo pipefail

# Colors and styling
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging functions
info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
highlight() { echo -e "${BOLD}$*${NC}"; }

# Configuration
readonly REPO_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main"
readonly SCRIPT_NAME="validator-stats.sh"
readonly COMMAND_NAME="aztec-stats"

# Installation paths
readonly INSTALL_DIR="${HOME}/.local/share/aztec-validator-tool"
readonly BIN_DIR="${HOME}/.local/bin"
readonly CONFIG_DIR="${HOME}/.config/aztec-validator"
readonly CACHE_DIR="${HOME}/.cache/aztec-validator"

# Error handling
cleanup_and_exit() {
    local exit_code=${1:-0}
    local message=${2:-""}
    
    [[ -n "$message" ]] && error "$message"
    exit "$exit_code"
}

trap 'cleanup_and_exit 1 "Installation failed unexpectedly"' ERR

# OS Detection
detect_os() {
    case "${OSTYPE:-}" in
        linux-gnu*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            elif grep -qi ubuntu /proc/version 2>/dev/null; then
                echo "ubuntu"
            else
                echo "linux"
            fi
            ;;
        darwin*) echo "macos" ;;
        *) echo "unknown" ;;
    esac
}

# Package manager detection
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Dependency management
check_dependencies() {
    local missing=()
    local required_tools=("curl" "jq" "bc")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        install_dependencies "${missing[@]}"
    else
        success "All dependencies are already installed"
    fi
}

install_dependencies() {
    local deps=("$@")
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    info "Installing dependencies: ${deps[*]}"
    
    case "$pkg_manager" in
        apt)
            sudo apt update && sudo apt install -y "${deps[@]}"
            ;;
        yum)
            sudo yum install -y "${deps[@]}"
            ;;
        dnf)
            sudo dnf install -y "${deps[@]}"
            ;;
        pacman)
            sudo pacman -S --noconfirm "${deps[@]}"
            ;;
        brew)
            brew install "${deps[@]}"
            ;;
        *)
            error "Unsupported package manager. Please install manually: ${deps[*]}"
            echo "Required tools:"
            echo "  - curl: for downloading files"
            echo "  - jq: for JSON processing"
            echo "  - bc: for mathematical calculations"
            cleanup_and_exit 1
            ;;
    esac
    
    success "Dependencies installed successfully"
}

# Directory creation
create_directories() {
    local dirs=(
        "$INSTALL_DIR"
        "$BIN_DIR" 
        "$CONFIG_DIR"
        "$CACHE_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if mkdir -p "$dir"; then
            info "Created directory: $dir"
        else
            error "Failed to create directory: $dir"
            cleanup_and_exit 1
        fi
    done
}

# Download and install script
download_script() {
    local script_url="${REPO_URL}/${SCRIPT_NAME}"
    local script_path="${INSTALL_DIR}/${SCRIPT_NAME}"
    
    info "Downloading validator stats script..."
    
    if curl -fsSL "$script_url" -o "$script_path"; then
        chmod +x "$script_path"
        success "Script downloaded and made executable"
    else
        error "Failed to download script from: $script_url"
        cleanup_and_exit 1
    fi
}

# Create wrapper script
create_wrapper() {
    local wrapper_path="${BIN_DIR}/${COMMAND_NAME}"
    
    info "Creating command wrapper..."
    
    cat > "$wrapper_path" <<EOF
#!/usr/bin/env bash
# Aztec Validator Tool Wrapper
# This script ensures the tool runs from the correct location

SCRIPT_DIR="\${HOME}/.local/share/aztec-validator-tool"
SCRIPT_PATH="\${SCRIPT_DIR}/validator-stats.sh"

if [[ ! -f "\$SCRIPT_PATH" ]]; then
    echo "Error: Aztec validator tool not found at \$SCRIPT_PATH"
    echo "Please reinstall using the installer script."
    exit 1
fi

# Execute the main script with all arguments
exec "\$SCRIPT_PATH" "\$@"
EOF
    
    chmod +x "$wrapper_path"
    success "Command wrapper created: $wrapper_path"
}

# PATH management
setup_path() {
    local shell_configs=(
        "${HOME}/.bashrc"
        "${HOME}/.zshrc" 
        "${HOME}/.profile"
    )
    
    local path_line='export PATH="$HOME/.local/bin:$PATH"'
    local added_to_config=0
    
    for config_file in "${shell_configs[@]}"; do
        if [[ -f "$config_file" ]]; then
            if ! grep -q "/.local/bin" "$config_file" 2>/dev/null; then
                {
                    echo ""
                    echo "# Added by Aztec Validator Tool installer"
                    echo "$path_line"
                } >> "$config_file"
                info "Added PATH to: $config_file"
                added_to_config=1
            fi
        fi
    done
    
    if [[ $added_to_config -eq 0 ]]; then
        # Create .profile if no config files exist
        local profile_file="${HOME}/.profile"
        {
            echo "# Created by Aztec Validator Tool installer"
            echo "$path_line"
        } > "$profile_file"
        info "Created $profile_file with PATH configuration"
    fi
    
    # Add to current session
    export PATH="$HOME/.local/bin:$PATH"
}

# Verification
verify_installation() {
    local wrapper_path="${BIN_DIR}/${COMMAND_NAME}"
    local script_path="${INSTALL_DIR}/${SCRIPT_NAME}"
    
    if [[ -x "$wrapper_path" && -x "$script_path" ]]; then
        success "Installation verification passed"
        return 0
    else
        error "Installation verification failed"
        [[ ! -x "$wrapper_path" ]] && error "Wrapper not executable: $wrapper_path"
        [[ ! -x "$script_path" ]] && error "Script not executable: $script_path"
        return 1
    fi
}

# Cleanup old installations
cleanup_old_installations() {
    local old_dirs=(
        "${HOME}/aztec-validator-tool"
        "${HOME}/.aztec-validator-tool"
    )
    
    for old_dir in "${old_dirs[@]}"; do
        if [[ -d "$old_dir" ]]; then
            info "Removing old installation: $old_dir"
            rm -rf "$old_dir"
        fi
    done
    
    # Remove old config files
    local old_configs=(
        "${HOME}/.aztec-validator-tool.conf"
    )
    
    for old_config in "${old_configs[@]}"; do
        if [[ -f "$old_config" ]]; then
            local new_config="${CONFIG_DIR}/config.conf"
            if [[ ! -f "$new_config" ]]; then
                info "Migrating old config to: $new_config"
                mv "$old_config" "$new_config"
            else
                info "Removing old config file: $old_config"
                rm -f "$old_config"
            fi
        fi
    done
}

# Print installation summary
print_summary() {
    local os
    os=$(detect_os)
    
    echo ""
    highlight "╔══════════════════════════════════════════════════════════════╗"
    highlight "║                 INSTALLATION COMPLETE! 🎉                   ║"
    highlight "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    success "✅ Aztec Validator Tool installed successfully!"
    echo ""
    
    echo "📁 Installation Details:"
    echo "   • Script location: ${INSTALL_DIR}/${SCRIPT_NAME}"
    echo "   • Command wrapper: ${BIN_DIR}/${COMMAND_NAME}"
    echo "   • Configuration: ${CONFIG_DIR}/"
    echo "   • Cache directory: ${CACHE_DIR}/"
    echo ""
    
    echo "🚀 Quick Start:"
    echo "   1. Reload your shell configuration:"
    case "$os" in
        "macos") echo "      source ~/.zshrc" ;;
        *) echo "      source ~/.bashrc" ;;
    esac
    echo ""
    echo "   2. Run the tool:"
    echo "      ${COMMAND_NAME} 0xYOUR_VALIDATOR_ADDRESS"
    echo ""
    
    echo "📖 Usage Examples:"
    echo "   # Basic validator stats"
    echo "   ${COMMAND_NAME} 0x581f8afba0ba7aa93c662e730559b63479ba70e3"
    echo ""
    echo "   # With epoch range and cookie setup"
    echo "   ${COMMAND_NAME} 0x581f8afba0ba7aa93c662e730559b63479ba70e3 \\"
    echo "     --epochs 1797:1897 --set-cookie"
    echo ""
    echo "   # Last 100 epochs with debug info"
    echo "   ${COMMAND_NAME} 0x581f8afba0ba7aa93c662e730559b63479ba70e3 \\"
    echo "     --last 100 --debug"
    echo ""
    
    echo "🔧 Troubleshooting:"
    echo "   • If command not found, run: source ~/.bashrc"
    echo "   • For Cloudflare issues, use: ${COMMAND_NAME} --set-cookie"
    echo "   • For help: ${COMMAND_NAME} --help"
    echo ""
    
    warn "⚠️  Important: If you encounter Cloudflare protection, you'll need to:"
    echo "   1. Visit https://dashtec.xyz in your browser"
    echo "   2. Get the cf_clearance cookie from Developer Tools"
    echo "   3. Run: ${COMMAND_NAME} your_address --set-cookie"
}

# Main installation process
main() {
    local os pkg_manager
    
    # Clear screen and show header
    clear || true
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          🚀 ENHANCED AZTEC VALIDATOR TOOL INSTALLER          ║"
    echo "║                    One-Click Setup                          ║"
    echo "║                   by Aabis Lone                             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # System detection
    os=$(detect_os)
    pkg_manager=$(detect_package_manager)
    
    info "🔍 System Detection:"
    echo "   • Operating System: $os"
    echo "   • Package Manager: $pkg_manager"
    echo ""
    
    # Pre-installation checks
    info "🧹 Cleaning up old installations..."
    cleanup_old_installations
    
    info "📦 Checking dependencies..."
    check_dependencies
    
    # Create directories
    info "📁 Creating directories..."
    create_directories
    
    # Download and install
    info "⬇️  Downloading latest version..."
    download_script
    
    # Create wrapper and setup PATH
    info "🔧 Setting up command wrapper..."
    create_wrapper
    
    info "🛤️  Configuring PATH..."
    setup_path
    
    # Verify installation
    info "✅ Verifying installation..."
    if verify_installation; then
        print_summary
        success "🎉 Installation completed successfully!"
    else
        cleanup_and_exit 1 "Installation verification failed"
    fi
}

# Execute main function
main "$@"
