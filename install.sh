#!/bin/bash
set -e

echo "🔧 Installing Aztec Validator Stats Tool..."

# Choose install dir
if [ -w /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
else
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    export PATH="$INSTALL_DIR:$PATH"
fi

# Download the latest script
SCRIPT_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main/validator-stats.sh"
SCRIPT_NAME="aztec-stats"

echo "⬇ Downloading script..."
curl -s -o "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# If ~/.local/bin was used, make sure it's in PATH permanently
if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]]; then
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
fi

echo "✅ Installation complete!"
echo ""
echo "Run: aztec-stats"
