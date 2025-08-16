#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            AZTEC VALIDATOR TOOL INSTALLER                   ║${NC}"
echo -e "${CYAN}║                   One-Click Setup                           ║${NC}"
echo -e "${CYAN}║                   by Aabis Lone                             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Universal install directory (works for all users)
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="aztec-stats"
SCRIPT_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main/validator-stats.sh"

# Create install directory
mkdir -p "$INSTALL_DIR"

echo -e "${BLUE}ℹ️  Checking system requirements...${NC}"

# Check dependencies
missing_deps=()
for dep in curl jq bc; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        missing_deps+=("$dep")
    fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Installing missing dependencies: ${missing_deps[*]}${NC}"
    
    # Detect OS and install
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Check if it's WSL or regular Linux
        if grep -qi microsoft /proc/version 2>/dev/null; then
            echo -e "${BLUE}ℹ️  Detected WSL environment${NC}"
        fi
        
        # Try to install without sudo first (for restricted environments)
        if ! sudo apt update && sudo apt install -y "${missing_deps[@]}" 2>/dev/null; then
            echo -e "${RED}❌ Failed to install dependencies automatically${NC}"
            echo -e "${YELLOW}Please install manually: sudo apt install ${missing_deps[*]}${NC}"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if ! command -v brew >/dev/null 2>&1; then
            echo -e "${RED}❌ Homebrew required. Install from: https://brew.sh${NC}"
            exit 1
        fi
        brew install "${missing_deps[@]}"
    else
        echo -e "${RED}❌ Unsupported OS. Please install manually: ${missing_deps[*]}${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ All dependencies satisfied${NC}"

echo -e "${BLUE}ℹ️  Installing to: $INSTALL_DIR${NC}"
echo -e "${BLUE}⬇️  Downloading latest script...${NC}"

# Download with better error handling
if curl -sSL -f --connect-timeout 10 --max-time 30 "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"; then
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    echo -e "${GREEN}✅ Download successful${NC}"
else
    echo -e "${RED}❌ Failed to download script. Please check:${NC}"
    echo -e "${YELLOW}  - Internet connection${NC}"
    echo -e "${YELLOW}  - GitHub repository access${NC}"
    echo -e "${YELLOW}  - Try again in a few minutes${NC}"
    exit 1
fi

# Smart PATH management - add to multiple shell configs
PATH_ADDED=false
for shell_config in ~/.bashrc ~/.zshrc ~/.profile ~/.bash_profile; do
    if [[ -f "$shell_config" ]]; then
        if ! grep -q "$INSTALL_DIR" "$shell_config" 2>/dev/null; then
            echo "" >> "$shell_config"
            echo "# Aztec Validator Tool - Added by installer" >> "$shell_config"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_config"
            echo -e "${GREEN}✅ Added to $shell_config${NC}"
            PATH_ADDED=true
        fi
    fi
done

# Add to current session PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    export PATH="$INSTALL_DIR:$PATH"
fi

echo ""
echo -e "${GREEN}🎉 Installation completed successfully!${NC}"
echo ""
echo -e "${CYAN}📖 Usage Examples:${NC}"
echo -e "${YELLOW}  aztec-stats 0xYOUR_VALIDATOR_ADDRESS${NC}                    # Complete stats overview"
echo -e "${YELLOW}  aztec-stats 0xYOUR_VALIDATOR_ADDRESS --epochs 1800:1900${NC} # Specific epoch range" 
echo -e "${YELLOW}  aztec-stats 0xYOUR_VALIDATOR_ADDRESS --last 120${NC}         # Last 120 epochs"
echo -e "${YELLOW}  aztec-stats 0xYOUR_VALIDATOR_ADDRESS --set-cookie${NC}       # Setup Cloudflare bypass"
echo ""
echo -e "${BLUE}📊 Complete Stats Overview:${NC}"
echo -e "${GREEN}   🌐 Network Stats (total validators, current epoch)${NC}"
echo -e "${GREEN}   ✅ Attestation Performance (total, successful, missed, rates)${NC}"
echo -e "${BLUE}   📋 Block Production (proposed, mined, missed, rates)${NC}"
echo -e "${RED}   🔨 Slashing History (recent events, your validator impact)${NC}"
echo -e "${YELLOW}   ⚠️  Accusations & Penalties${NC}"
echo -e "${CYAN}   👥 Committee Participation${NC}"
echo -e "${PURPLE}   🏆 Top Validators Ranking (when epoch range provided)${NC}"
echo ""
echo -e "${BLUE}💡 Cloudflare Protection:${NC}"
echo -e "${YELLOW}  If requests get blocked, setup cookie once:${NC}"
echo -e "${YELLOW}  aztec-stats 0xYOUR_VALIDATOR_ADDRESS --set-cookie${NC}"
echo ""
if [[ "$PATH_ADDED" == "true" ]]; then
    echo -e "${GREEN}🔄 Restart your terminal or run: source ~/.bashrc${NC}"
else
    echo -e "${GREEN}✅ Tool is ready to use immediately!${NC}"
fi
echo -e "${BLUE}📁 Installation path: $INSTALL_DIR/$SCRIPT_NAME${NC}"
