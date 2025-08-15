#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════════"
echo "║            AZTEC VALIDATOR TOOL INSTALLER           ║"
echo "║                   One-Click Setup                   ║"
echo "║                   by Aabis Lone                     ║"
echo "═══════════════════════════════════════════════════════"
echo ""

# Detect OS type
OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
echo "ℹ Detected OS: $OS_TYPE"
echo "ℹ Checking dependencies…"

# Ensure required tools are installed
for cmd in curl jq; do
    if ! command -v $cmd &>/dev/null; then
        echo "❌ Missing dependency: $cmd"
        echo "   Please install it first."
        exit 1
    fi
done

# Installation path in user's bin directory
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="aztec-stats"
SCRIPT_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main/validator-stats.sh"

# Create bin directory if missing
mkdir -p "$INSTALL_DIR"

echo "ℹ Downloading validator stats script…"
curl -s -o "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Make sure ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
fi

echo "✓ Installation complete!"
echo ""
echo "How to run:"
echo "  aztec-stats"
