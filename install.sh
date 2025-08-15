#!/bin/bash
set -e

echo "🔧 Installing Aztec Validator Stats Tool..."

# Decide where to install
if [ -w /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
else
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
fi

SCRIPT_URL="https://raw.githubusercontent.com/Aabis5004/aztec-validator-tool/main/validator-stats.sh"
SCRIPT_NAME="aztec-stats"

echo "⬇ Downloading script..."
curl -s -o "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Add ~/.local/bin to PATH for current session & future sessions
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    export PATH="$INSTALL_DIR:$PATH"
    if ! grep -q "$INSTALL_DIR" ~/.bashrc; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> ~/.bashrc
    fi
fi

# If installed in ~/.local/bin, create a symlink in /usr/local/bin if possible (for instant use)
if [ "$INSTALL_DIR" = "$HOME/.local/bin" ] && [ -w /usr/local/bin ]; then
    ln -sf "$INSTALL_DIR/$SCRIPT_NAME" /usr/local/bin/$SCRIPT_NAME
fi

echo "✅ Installation complete!"
echo ""
echo "Run: aztec-stats"
