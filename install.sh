#!/bin/bash
set -e

INSTALL_DIR="$HOME/aztec-validator-tool"
SCRIPT_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main/validator-stats.sh"

echo "🔧 Installing Aztec Validator Stats Tool..."
mkdir -p "$INSTALL_DIR"

echo "⬇ Downloading script..."
curl -s -o "$INSTALL_DIR/validator-stats.sh" "$SCRIPT_URL"
chmod +x "$INSTALL_DIR/validator-stats.sh"

# Add alias if not exists
if ! grep -q "aztec-stats" ~/.bashrc; then
    echo "alias aztec-stats='$INSTALL_DIR/validator-stats.sh'" >> ~/.bashrc
fi

echo "✅ Installation complete!"
echo ""
echo "Run: aztec-stats"
