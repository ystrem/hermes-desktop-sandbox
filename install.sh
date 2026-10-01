#!/bin/bash
# Cleanup legacy system files and enforce self-contained portable mode
set -euo pipefail

PROFILE_DIR="${HOME}/.config/firejail"
BIN_DIR="${HOME}/.local/bin"
DESKTOP_FILE="${HOME}/.local/share/applications/hermes-desktop-sandbox.desktop"

echo "==> Cleaning up legacy files from system directories..."
rm -f "${PROFILE_DIR}/hermes-desktop.local" \
      "${PROFILE_DIR}/hermes-desktop.net" \
      "${BIN_DIR}/hermes-desktop-sandbox" \
      "${DESKTOP_FILE}" \
      "${BIN_DIR}"/Hermes-*.AppImage 2>/dev/null || true

echo "  ✓ Cleaned ${PROFILE_DIR}/hermes-desktop.local"
echo "  ✓ Cleaned ${PROFILE_DIR}/hermes-desktop.net"
echo "  ✓ Cleaned ${BIN_DIR}/hermes-desktop-sandbox"
echo "  ✓ Cleaned ${DESKTOP_FILE}"

echo ""
echo "✨ Hermes Desktop Sandbox is 100% Self-Contained & Portable!"
echo "   No system installation or files outside this directory are used."
echo ""
echo "   Run directly inside this directory:"
echo "     ./run-hermes-desktop.sh"
echo ""



