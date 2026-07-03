#!/bin/bash
# Hermes Desktop — Firejail sandboxed launcher
# Auto-detects the latest AppImage in the release directory

set -euo pipefail

HERMES_RELEASE="${HOME}/.hermes/hermes-agent/apps/desktop/release"
PROFILE_DIR="${HOME}/.config/firejail"
PROFILE="${PROFILE_DIR}/hermes-desktop.local"

# Find the latest Hermes AppImage
APPIMAGE=$(find "${HERMES_RELEASE}" -name "Hermes-*.AppImage" -type f 2>/dev/null | sort -V | tail -1)

if [ -z "${APPIMAGE}" ]; then
    echo "Error: No Hermes AppImage found in ${HERMES_RELEASE}"
    echo "Build it first: cd ~/.hermes/hermes-agent/apps/desktop && npm run dist:linux"
    exit 1
fi

if [ ! -f "${PROFILE}" ]; then
    echo "Warning: Firejail profile not found at ${PROFILE}"
    echo "Run install.sh or copy hermes-desktop.local to ${PROFILE}"
    echo "Falling back to default firejail sandbox..."
    firejail --private-tmp --noroot --caps.drop=all \
        --read-only="${HOME}" \
        --read-write="${HOME}/.hermes" \
        --blacklist="${HOME}/.ssh" \
        --blacklist="${HOME}/.gnupg" \
        --nodbus \
        "${APPIMAGE}"
else
    firejail --profile="${PROFILE}" "${APPIMAGE}"
fi
