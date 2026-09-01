#!/bin/bash
# Hermes Desktop — Firejail sandboxed launcher
# Auto-detects local AppImages / unpacked binaries, or downloads prebuilt releases from GitHub

set -euo pipefail

PROFILE_DIR="${HOME}/.config/firejail"
PROFILE="${PROFILE_DIR}/hermes-desktop.local"
RELEASE_REPO="ystrem/hermes-desktop-sandbox"
DOWNLOAD_DIR="${HOME}/.local/bin"

show_help() {
    echo "Usage: hermes-desktop-sandbox [OPTIONS] [ELECTRON_ARGS...]"
    echo ""
    echo "Launch the Hermes Desktop AppImage inside a Firejail sandbox."
    echo ""
    echo "Environment variables:"
    echo "  HERMES_APPIMAGE   Path to custom Hermes AppImage or executable"
    echo ""
    echo "Options:"
    echo "  --update, --download   Download / update the latest pre-built AppImage from GitHub"
    echo "  -h, --help             Show this help message and exit"
    echo ""
    exit 0
}

download_latest_release() {
    echo "==> Fetching latest pre-built Hermes Desktop release from GitHub (${RELEASE_REPO})..."
    local release_json asset_url file_name
    release_json=$(curl -sSH "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" 2>/dev/null || echo "")

    if [ -z "${release_json}" ] || echo "${release_json}" | grep -q "Not Found"; then
        echo "Error: Could not fetch latest release from https://api.github.com/repos/${RELEASE_REPO}/releases/latest"
        echo "Ensure the repository is public and GitHub Actions has published a release."
        exit 1
    fi

    asset_url=$(echo "${release_json}" | jq -r '.assets[] | select(.name | endswith(".AppImage")) | .browser_download_url' | head -n 1)
    file_name=$(echo "${release_json}" | jq -r '.assets[] | select(.name | endswith(".AppImage")) | .name' | head -n 1)
    local tag_name=$(echo "${release_json}" | jq -r '.tag_name')

    if [ -z "${asset_url}" ] || [ "${asset_url}" = "null" ]; then
        echo "Error: No .AppImage asset found in latest GitHub release (${tag_name})."
        exit 1
    fi

    mkdir -p "${DOWNLOAD_DIR}"
    local target_path="${DOWNLOAD_DIR}/${file_name}"

    echo "==> Downloading ${file_name} (${tag_name}) to ${DOWNLOAD_DIR}..."
    curl -L --progress-bar -o "${target_path}" "${asset_url}"
    chmod +x "${target_path}"
    echo "  ✓ Download complete: ${target_path}"
    APPIMAGE="${target_path}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
fi

if [[ "${1:-}" == "--update" || "${1:-}" == "--download" ]]; then
    download_latest_release
    shift
fi

# Locate local AppImage or unpacked binary
APPIMAGE="${APPIMAGE:-}"

if [ -z "${APPIMAGE}" ]; then
    if [ -n "${HERMES_APPIMAGE:-}" ] && [ -e "${HERMES_APPIMAGE}" ]; then
        APPIMAGE="${HERMES_APPIMAGE}"
    else
        # Candidate search paths (in priority order)
        SEARCH_DIRS=(
            "${HOME}/.local/bin"
            "${HOME}/.hermes/hermes-agent/apps/desktop/release"
            "/usr/local/lib/hermes-agent/apps/desktop/release"
            "${HOME}/Applications"
            "."
        )

        for dir in "${SEARCH_DIRS[@]}"; do
            if [ -d "${dir}" ]; then
                # Check for .AppImage files
                FOUND=$(find "${dir}" -maxdepth 2 -name "Hermes-*.AppImage" -type f 2>/dev/null | sort -V | tail -1)
                if [ -n "${FOUND}" ]; then
                    APPIMAGE="${FOUND}"
                    break
                fi
                # Check for unpacked linux executable
                if [ -x "${dir}/linux-unpacked/hermes-desktop" ]; then
                    APPIMAGE="${dir}/linux-unpacked/hermes-desktop"
                    break
                fi
            fi
        done
    fi
fi

# If still not found, offer to download automatically
if [ -z "${APPIMAGE}" ]; then
    echo "No local Hermes AppImage or executable found."
    echo "Attempting automatic download of pre-built release from GitHub..."
    download_latest_release
fi

# Non-blocking update check (quick 1s timeout to avoid slowing down startup)
(
    latest_tag=$(curl -s --connect-timeout 1 -m 2 -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" 2>/dev/null | jq -r '.tag_name' 2>/dev/null || echo "")
    if [ -n "${latest_tag}" ] && [ "${latest_tag}" != "null" ]; then
        current_name=$(basename "${APPIMAGE}")
        if [[ "${current_name}" != *"${latest_tag}"* ]]; then
            echo "💡 Tip: A new Hermes Desktop release (${latest_tag}) is available!" >&2
            echo "   Run 'hermes-desktop-sandbox --update' to download it." >&2
        fi
    fi
) &>/dev/null &

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


