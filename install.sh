#!/bin/bash
# Install Hermes Desktop Firejail sandbox & desktop launcher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_SRC="${SCRIPT_DIR}/hermes-desktop.local"
NETFILTER_SRC="${SCRIPT_DIR}/hermes-desktop.net"
WRAPPER_SRC="${SCRIPT_DIR}/run-hermes-desktop.sh"
PROFILE_DIR="${HOME}/.config/firejail"
BIN_DIR="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/hermes-desktop-sandbox.desktop"

show_help() {
    echo "Usage: install.sh [OPTIONS]"
    echo ""
    echo "Install or uninstall the Hermes Desktop Firejail sandbox."
    echo ""
    echo "Options:"
    echo "  --uninstall    Remove installed Firejail profiles, wrapper script, and desktop launcher"
    echo "  -h, --help     Show this help message and exit"
    echo ""
    exit 0
}

do_uninstall() {
    echo "==> Uninstalling Hermes Desktop Sandbox..."
    rm -f "${PROFILE_DIR}/hermes-desktop.local"
    rm -f "${PROFILE_DIR}/hermes-desktop.net"
    rm -f "${BIN_DIR}/hermes-desktop-sandbox"
    rm -f "${DESKTOP_FILE}"
    echo "  ✓ Removed ${PROFILE_DIR}/hermes-desktop.local"
    echo "  ✓ Removed ${PROFILE_DIR}/hermes-desktop.net"
    echo "  ✓ Removed ${BIN_DIR}/hermes-desktop-sandbox"
    echo "  ✓ Removed ${DESKTOP_FILE}"
    echo "==> Uninstall complete!"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall)
            do_uninstall
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run 'install.sh --help' for usage."
            exit 1
            ;;
    esac
done

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
cp "${NETFILTER_SRC}" "${PROFILE_DIR}/hermes-desktop.net"
echo "  → ${PROFILE_DIR}/hermes-desktop.local"
echo "  → ${PROFILE_DIR}/hermes-desktop.net"

echo ""
echo "==> ⚠️  Edit netfilter rules before first run!"
echo "    Set your allowed local IP in: ${PROFILE_DIR}/hermes-desktop.net"
echo "    Uncomment the line with your AI worker / aicore IP"
echo ""

echo "==> Installing wrapper script..."
mkdir -p "${BIN_DIR}"
cp "${WRAPPER_SRC}" "${BIN_DIR}/hermes-desktop-sandbox"
chmod +x "${BIN_DIR}/hermes-desktop-sandbox"
echo "  → ${BIN_DIR}/hermes-desktop-sandbox"

echo "==> Installing Desktop Menu entry..."
mkdir -p "${DESKTOP_DIR}"
cat <<EOF > "${DESKTOP_FILE}"
[Desktop Entry]
Name=Hermes Desktop (Sandboxed)
Comment=Sandboxed Electron desktop app for Hermes AI Agent
Exec=${BIN_DIR}/hermes-desktop-sandbox %U
Icon=hermes
Terminal=false
Type=Application
Categories=Utility;Development;
StartupWMClass=hermes-desktop
EOF
chmod +x "${DESKTOP_FILE}"
echo "  → ${DESKTOP_FILE}"

# Check if BIN_DIR is in PATH
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "⚠️  ${BIN_DIR} is not in your PATH."
    echo "   Add this to your ~/.bashrc or ~/.zshrc:"
    echo "   export PATH=\"\${PATH}:${BIN_DIR}\""
fi

# Check if an AppImage or executable already exists
FOUND_APPIMAGE=""
if [ -n "${HERMES_APPIMAGE:-}" ] && [ -e "${HERMES_APPIMAGE}" ]; then
    FOUND_APPIMAGE="${HERMES_APPIMAGE}"
else
    SEARCH_DIRS=(
        "${BIN_DIR}"
        "${HOME}/.hermes/hermes-agent/apps/desktop/release"
        "/usr/local/lib/hermes-agent/apps/desktop/release"
        "${HOME}/Applications"
    )
    for dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "${dir}" ]; then
            FOUND=$(find "${dir}" -maxdepth 2 -name "Hermes-*.AppImage" -type f 2>/dev/null | sort -V | tail -1)
            if [ -n "${FOUND}" ]; then
                FOUND_APPIMAGE="${FOUND}"
                break
            fi
            if [ -x "${dir}/linux-unpacked/hermes-desktop" ]; then
                FOUND_APPIMAGE="${dir}/linux-unpacked/hermes-desktop"
                break
            fi
        fi
    done
fi

if [ -n "${FOUND_APPIMAGE}" ]; then
    echo "  ✓ Found local executable: ${FOUND_APPIMAGE}"
else
    echo "  ⚠️  No local Hermes AppImage found."
    echo "  ==> Attempting to fetch latest pre-built AppImage from GitHub Releases..."
    if "${BIN_DIR}/hermes-desktop-sandbox" --download; then
        echo "  ✓ Pre-built AppImage downloaded successfully!"
    else
        echo "  ⚠️  Could not download prebuilt release. You can build it locally:"
        echo "     cd ~/.hermes/hermes-agent/apps/desktop && npm run pack"
    fi
fi

echo ""
echo "==> Done!"
echo "Before first run, edit your network rules:"
echo "  vim ${PROFILE_DIR}/hermes-desktop.net"
echo ""
echo "Then launch via application menu or run:  hermes-desktop-sandbox"
echo "To update to the latest release anytime:  hermes-desktop-sandbox --update"
echo ""


