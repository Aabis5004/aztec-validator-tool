#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════"
echo "║            AZTEC VALIDATOR TOOL INSTALLER        ║"
echo "║                   One-Click Setup                ║"
echo "║                   by Aabis Lone                  ║"
echo "═══════════════════════════════════════════════════"
echo ""

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="aztec-stats"
SCRIPT_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main/validator-stats.sh"

# Ensure local bin exists
mkdir -p "$INSTALL_DIR"

echo "ℹ Checking dependencies..."
command -v curl >/dev/null || { echo "❌ curl not found. Install it first."; exit 1; }

echo "ℹ Installing into: $INSTALL_DIR"
echo "⬇ Downloading script..."
curl -s -o "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Add to PATH instantly for this session and permanently
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    export PATH="$INSTALL_DIR:$PATH"
    if ! grep -q "$INSTALL_DIR" ~/.bashrc; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> ~/.bashrc
    fi
fi

echo "✅ Installation complete!"
echo ""
echo "How to run:"
echo "  aztec-stats 0xYOUR_ADDRESS --epochs 1797:1897"
echo "  aztec-stats 0xYOUR_ADDRESS --last 120 --set-cookie"
echo ""
echo "If Cloudflare blocks requests, set your cookie once:"
echo "  aztec-stats 0xYOUR_ADDRESS --set-cookie"
