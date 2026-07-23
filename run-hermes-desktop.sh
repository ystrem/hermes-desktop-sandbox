#!/bin/bash
# Hermes Desktop — Firejail sandboxed launcher
# Auto-detects the latest AppImage in release/install directories or uses HERMES_APPIMAGE

set -euo pipefail

PROFILE_DIR="${HOME}/.config/firejail"
PROFILE="${PROFILE_DIR}/hermes-desktop.local"

show_help() {
    echo "Usage: hermes-desktop-sandbox [OPTIONS] [ELECTRON_ARGS...]"
    echo ""
    echo "Launch the Hermes Desktop AppImage inside a Firejail sandbox."
    echo ""
    echo "Environment variables:"
    echo "  HERMES_APPIMAGE   Path to custom Hermes AppImage file"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message and exit"
    echo ""
    exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
fi

# Locate the Hermes AppImage
APPIMAGE=""

if [ -n "${HERMES_APPIMAGE:-}" ] && [ -f "${HERMES_APPIMAGE}" ]; then
    APPIMAGE="${HERMES_APPIMAGE}"
else
    # Candidate search paths (in priority order)
    SEARCH_DIRS=(
        "${HOME}/.hermes/hermes-agent/apps/desktop/release"
        "/usr/local/lib/hermes-agent/apps/desktop/release"
        "${HOME}/Applications"
        "${HOME}/.local/bin"
        "."
    )

    for dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "${dir}" ]; then
            FOUND=$(find "${dir}" -maxdepth 2 -name "Hermes-*.AppImage" -type f 2>/dev/null | sort -V | tail -1)
            if [ -n "${FOUND}" ]; then
                APPIMAGE="${FOUND}"
                break
            fi
        fi
    done
fi

if [ -z "${APPIMAGE}" ]; then
    echo "Error: No Hermes AppImage found."
    echo "Set HERMES_APPIMAGE=/path/to/Hermes-*.AppImage or build it first:"
    echo "  cd ~/.hermes/hermes-agent/apps/desktop && npm run dist:linux"
    exit 1
fi

if [ ! -f "${PROFILE}" ]; then
    echo "Warning: Firejail profile not found at ${PROFILE}"
    echo "Run install.sh or copy hermes-desktop.local to ${PROFILE}"
    echo "Falling back to default firejail sandbox..."
    exec firejail --private-tmp --noroot --caps.drop=all \
        --read-only="${HOME}" \
        --read-write="${HOME}/.hermes" \
        --blacklist="${HOME}/.ssh" \
        --blacklist="${HOME}/.gnupg" \
        --nodbus \
        "${APPIMAGE}" "$@"
else
    exec firejail --profile="${PROFILE}" "${APPIMAGE}" "$@"
fi

