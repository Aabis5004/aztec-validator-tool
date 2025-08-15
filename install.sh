#!/bin/bash
set -e

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}║            AZTEC VALIDATOR TOOL INSTALLER        ║${NC}"
echo -e "${CYAN}║                   One-Click Setup                ║${NC}"
echo -e "${CYAN}║                   by Aabis Lone                  ║${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="aztec-stats"
SCRIPT_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main/validator-stats.sh"

# Create install directory
mkdir -p "$INSTALL_DIR"

echo -e "${BLUE}ℹ️  Checking system requirements...${NC}"

# Check dependencies
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}❌ curl is required but not installed.${NC}"
    echo -e "${YELLOW}Install with: sudo apt install curl (Ubuntu/Debian) or brew install curl (macOS)${NC}"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  jq not found. Installing...${NC}"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt update && sudo apt install -y jq 2>/dev/null || {
            echo -e "${RED}❌ Failed to install jq. Please install manually: sudo apt install jq${NC}"
            exit 1
        }
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq 2>/dev/null || {
            echo -e "${RED}❌ Failed to install jq. Please install manually: brew install jq${NC}"
            exit 1
        }
    else
        echo -e "${RED}❌ Please install jq manually for your system${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ All dependencies satisfied${NC}"

echo -e "${BLUE}ℹ️  Installing to: $INSTALL_DIR${NC}"
echo -e "${BLUE}⬇️  Downloading latest script...${NC}"

# Download with better error handling
if curl -sSL -f "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"; then
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    echo -e "${GREEN}✅ Download successful${NC}"
else
    echo -e "${RED}❌ Failed to download script. Check your internet connection.${NC}"
    exit 1
fi

# Add to PATH for current session and permanently
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    export PATH="$INSTALL_DIR:$PATH"
    
    # Add to shell config files
    for config_file in ~/.bashrc ~/.zshrc ~/.profile; do
        if [[ -f "$config_file" ]] && ! grep -q "$INSTALL_DIR" "$config_file"; then
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$config_file"
            echo -e "${GREEN}✅ Added to $config_file${NC}"
        fi
    done
fi

echo ""
echo -e "${GREEN}🎉 Installation completed successfully!${NC}"
echo ""
echo -e "${CYAN}📖 Usage Examples:${NC}"
echo -e "${YELLOW}  aztec-stats 0xYOUR_ADDRESS${NC}                          # Basic stats"
echo -e "${YELLOW}  aztec-stats 0xYOUR_ADDRESS --last 120${NC}               # Last 120 epochs"
echo -e "${YELLOW}  aztec-stats 0xYOUR_ADDRESS --epochs 1797:1897${NC}       # Specific range"
echo -e "${YELLOW}  aztec-stats 0xYOUR_ADDRESS --set-cookie${NC}             # Set Cloudflare cookie"
echo ""
echo -e "${BLUE}💡 Tip: If Cloudflare blocks requests, set your cookie once:${NC}"
echo -e "${YELLOW}  aztec-stats 0xYOUR_ADDRESS --set-cookie${NC}"
echo ""
echo -e "${GREEN}🔄 Restart your terminal or run: source ~/.bashrc${NC}"
