#!/bin/bash

# Aztec Validator Tool - One-Click Installer
# Works on: Ubuntu, WSL, macOS, and most Linux distributions

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if grep -qi microsoft /proc/version 2>/dev/null; then
            OS="wsl"
        else
            OS="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="mac"
    else
        OS="unknown"
    fi
}

install_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v bc &> /dev/null; then
        missing_deps+=("bc")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_warning "Installing missing dependencies: ${missing_deps[*]}"
        
        case $OS in
            "wsl"|"linux")
                print_info "Updating package list..."
                sudo apt update
                print_info "Installing dependencies..."
                sudo apt install -y "${missing_deps[@]}"
                ;;
            "mac")
                if command -v brew &> /dev/null; then
                    brew install "${missing_deps[@]}"
                else
                    print_error "Please install Homebrew first: https://brew.sh"
                    exit 1
                fi
                ;;
            *)
                print_error "Unsupported operating system: $OSTYPE"
                exit 1
                ;;
        esac
        
        print_success "Dependencies installed successfully!"
    else
        print_success "All dependencies already installed!"
    fi
}

main() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            AZTEC VALIDATOR TOOL INSTALLER                   ║"
    echo "║                   One-Click Setup                           ║"
    echo "║                   by Aabis Lone                             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    detect_os
    print_info "Detected OS: $OS"
    echo ""
    
    # Check and install dependencies
    print_info "Checking dependencies..."
    install_dependencies
    echo ""
    
    # Create project directory
    INSTALL_DIR="$HOME/aztec-validator-tool"
    print_info "Creating installation directory: $INSTALL_DIR"
    
    # Remove old installation if exists
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Found existing installation. Updating..."
        rm -rf "$INSTALL_DIR"
    fi
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Download the main script from GitHub
    print_info "Downloading validator stats script..."
    
    # Replace YOUR_GITHUB_USERNAME with your actual username
    GITHUB_URL="https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/aztec-validator-tool/main/validator-stats.sh"
    
    if ! curl -s -f "$GITHUB_URL" -o validator-stats.sh; then
        print_error "Failed to download script from GitHub"
        print_info "Please check:"
        echo "  • Your internet connection"
        echo "  • The repository is public"
        echo "  • The file exists at: $GITHUB_URL"
        exit 1
    fi
    
    chmod +x validator-stats.sh
    
    # Create a convenient wrapper script
    cat > aztec-stats << 'EOF'
#!/bin/bash
cd "$HOME/aztec-validator-tool"
./validator-stats.sh "$@"
EOF
    chmod +x aztec-stats
    
    # Add to PATH (optional)
    if ! grep -q "$INSTALL_DIR" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo "# Aztec Validator Tool" >> ~/.bashrc
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> ~/.bashrc
        print_info "Added to PATH. Restart terminal or run: source ~/.bashrc"
    fi
    
    print_success "Installation complete!"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                       HOW TO USE                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📍 Installation path: $INSTALL_DIR"
    echo ""
    echo "🎯 Method 1 - Direct:"
    echo "   cd $INSTALL_DIR"
    echo "   ./validator-stats.sh <validator_address>"
    echo ""
    echo "🎯 Method 2 - Global command (after restart/source ~/.bashrc):"
    echo "   aztec-stats <validator_address>"
    echo ""
    echo "📝 Example:"
    echo "   ./validator-stats.sh 0x581f8afba0ba7aa93c662e730559b63479ba70e3"
    echo ""
    echo "🆘 Need help? Visit: https://github.com/YOUR_GITHUB_USERNAME/aztec-validator-tool"
    echo ""
}

main "$@"
