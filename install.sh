#!/bin/bash
# Install Hermes Desktop Firejail sandbox
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_SRC="${SCRIPT_DIR}/hermes-desktop.local"
WRAPPER_SRC="${SCRIPT_DIR}/run-hermes-desktop.sh"
PROFILE_DIR="${HOME}/.config/firejail"
BIN_DIR="${HOME}/.local/bin"

echo "==> Checking Firejail..."
if ! command -v firejail &>/dev/null; then
    echo "Firejail is not installed. Install it first:"
    echo "  sudo pacman -S firejail    # Arch/CachyOS"
    echo "  sudo apt install firejail  # Debian/Ubuntu"
    exit 1
fi

echo "==> Copying Firejail profile..."
mkdir -p "${PROFILE_DIR}"
cp "${PROFILE_SRC}" "${PROFILE_DIR}/hermes-desktop.local"
echo "  → ${PROFILE_DIR}/hermes-desktop.local"

echo "==> Installing wrapper script..."
mkdir -p "${BIN_DIR}"
cp "${WRAPPER_SRC}" "${BIN_DIR}/hermes-desktop-sandbox"
chmod +x "${BIN_DIR}/hermes-desktop-sandbox"
echo "  → ${BIN_DIR}/hermes-desktop-sandbox"

# Check if BIN_DIR is in PATH
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "⚠️  ${BIN_DIR} is not in your PATH."
    echo "   Add this to your ~/.bashrc or ~/.zshrc:"
    echo "   export PATH=\"\${PATH}:${BIN_DIR}\""
fi

echo ""
echo "==> Checking for Hermes desktop build..."
HERMES_RELEASE="${HOME}/.hermes/hermes-agent/apps/desktop/release"
if [ -d "${HERMES_RELEASE}" ]; then
    COUNT=$(find "${HERMES_RELEASE}" -name "Hermes-*.AppImage" 2>/dev/null | wc -l)
    if [ "${COUNT}" -gt 0 ]; then
        echo "  Found ${COUNT} AppImage(s) in ${HERMES_RELEASE}"
    else
        echo "  ⚠️  No Hermes AppImage found. Build it first:"
        echo "     cd ~/.hermes/hermes-agent/apps/desktop && npm run dist:linux"
    fi
else
    echo "  ⚠️  Release directory not found. Build the desktop first:"
    echo "     cd ~/.hermes/hermes-agent/apps/desktop && npm run dist:linux"
fi

echo ""
echo "==> Done!"
echo "Run sandboxed Hermes desktop:   hermes-desktop-sandbox"
echo ""
