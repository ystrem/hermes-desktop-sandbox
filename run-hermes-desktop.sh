#!/bin/bash
# Hermes Desktop — Firejail sandboxed launcher
# Auto-detects local AppImages / unpacked binaries, or downloads prebuilt releases from GitHub

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${HERMES_PROFILE:-${SCRIPT_DIR}/hermes-desktop.local}"
DOWNLOAD_DIR="${HERMES_BIN_DIR:-${SCRIPT_DIR}}"

# Auto-detect GitHub release repository from environment or git remote URL
if [ -n "${HERMES_SANDBOX_REPO:-}" ]; then
    RELEASE_REPO="${HERMES_SANDBOX_REPO}"
else
    DETECTED_REPO=$(git -C "${SCRIPT_DIR}" config --get remote.origin.url 2>/dev/null | sed -E 's/.*[:\/]([^\/]+\/[^\/.]+)(\.git)?$/\1/' || echo "")
    RELEASE_REPO="${DETECTED_REPO:-ystrem/hermes-desktop-sandbox}"
fi



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
    local release_json asset_url file_name tag_name
    release_json=$(curl -sSH "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" 2>/dev/null || echo "")

    if [ -z "${release_json}" ] || echo "${release_json}" | grep -q "Not Found"; then
        echo "Error: Could not fetch latest release from https://api.github.com/repos/${RELEASE_REPO}/releases/latest"
        echo "Ensure the repository is public and GitHub Actions has published a release."
        exit 1
    fi

    tag_name=$(echo "${release_json}" | jq -r '.tag_name')

    # Prefer native .tar.gz package, fallback to .AppImage
    asset_url=$(echo "${release_json}" | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url' | head -n 1)
    file_name=$(echo "${release_json}" | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .name' | head -n 1)

    if [ -z "${asset_url}" ] || [ "${asset_url}" = "null" ]; then
        asset_url=$(echo "${release_json}" | jq -r '.assets[] | select(.name | endswith(".AppImage")) | .browser_download_url' | head -n 1)
        file_name=$(echo "${release_json}" | jq -r '.assets[] | select(.name | endswith(".AppImage")) | .name' | head -n 1)
    fi

    if [ -z "${asset_url}" ] || [ "${asset_url}" = "null" ]; then
        echo "Error: No .tar.gz or .AppImage asset found in latest GitHub release (${tag_name})."
        exit 1
    fi

    mkdir -p "${DOWNLOAD_DIR}"
    local target_path="${DOWNLOAD_DIR}/${file_name}"

    echo "==> Downloading ${file_name} (${tag_name}) to ${DOWNLOAD_DIR}..."
    curl -L --progress-bar -o "${target_path}" "${asset_url}"
    
    if [[ "${file_name}" == *.tar.gz ]]; then
        local app_dir="${DOWNLOAD_DIR}/hermes-desktop-app"
        echo "==> Extracting native Linux package to ${app_dir}..."
        mkdir -p "${app_dir}"
        tar -xzf "${target_path}" -C "${app_dir}"
        chmod +x "${app_dir}/hermes-desktop" 2>/dev/null || true
        APPIMAGE="${app_dir}/hermes-desktop"
    else
        chmod +x "${target_path}"
        APPIMAGE="${target_path}"
    fi

    echo "  ✓ Download and extraction complete: ${APPIMAGE}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
fi

if [[ "${1:-}" == "--update" || "${1:-}" == "--download" ]]; then
    download_latest_release
    shift
fi

# Locate local binary or unpacked package
APPIMAGE="${APPIMAGE:-}"

if [ -z "${APPIMAGE}" ]; then
    if [ -n "${HERMES_APPIMAGE:-}" ] && [ -e "${HERMES_APPIMAGE}" ]; then
        APPIMAGE="${HERMES_APPIMAGE}"
    else
        # Candidate search paths (strictly inside repository folder)
        SEARCH_DIRS=(
            "${SCRIPT_DIR}/hermes-desktop-app"
            "${SCRIPT_DIR}"
        )


        for dir in "${SEARCH_DIRS[@]}"; do
            if [ -d "${dir}" ]; then
                # Check for direct native binary
                if [ -x "${dir}/hermes-desktop" ]; then
                    APPIMAGE="${dir}/hermes-desktop"
                    break
                fi
                if [ -x "${dir}/linux-unpacked/hermes-desktop" ]; then
                    APPIMAGE="${dir}/linux-unpacked/hermes-desktop"
                    break
                fi
                # Check for .AppImage files
                FOUND=$(find "${dir}" -maxdepth 2 -name "Hermes-*.AppImage" -type f 2>/dev/null | sort -V | tail -1)
                if [ -n "${FOUND}" ]; then
                    APPIMAGE="${FOUND}"
                    break
                fi
            fi
        done
    fi
fi

# If still not found, offer to download automatically
if [ -z "${APPIMAGE}" ]; then
    echo "No local Hermes executable or package found."
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
            echo "   Run './run-hermes-desktop.sh --update' to download it." >&2
        fi
    fi
) &>/dev/null &

# If target is an AppImage, extract it once locally to eliminate FUSE runtime issues completely
if [[ "${APPIMAGE}" == *.AppImage ]]; then
    local_app_dir="${SCRIPT_DIR}/hermes-desktop-app"
    if [ ! -x "${local_app_dir}/AppRun" ] && [ ! -x "${local_app_dir}/hermes-desktop" ]; then
        echo "==> Unpacking AppImage into local repo directory (${local_app_dir})..."
        mkdir -p "${local_app_dir}"
        (
            cd "${SCRIPT_DIR}"
            "${APPIMAGE}" --appimage-extract >/dev/null 2>&1 || true
            if [ -d "squashfs-root" ]; then
                cp -r squashfs-root/* "${local_app_dir}/"
                rm -rf squashfs-root
            fi
        )
    fi
    if [ -x "${local_app_dir}/AppRun" ]; then
        APPIMAGE="${local_app_dir}/AppRun"
    elif [ -x "${local_app_dir}/hermes-desktop" ]; then
        APPIMAGE="${local_app_dir}/hermes-desktop"
    fi
fi

# Ensure required Hermes config, plugin, and user data directories exist
mkdir -p "${HOME}/.hermes" "${HOME}/.hermes/plugins" "${HOME}/.hermes/desktop-plugins"
mkdir -p "${HOME}/.config/Hermes" "${HOME}/.config/hermes-desktop" "${HOME}/.config/Hermes Desktop" "${HOME}/.config/hermes"
touch "${HOME}/.config/kbuildsycoca6rc" 2>/dev/null || true



APPIMAGE_FLAGS=()
if [[ "${APPIMAGE}" == *.AppImage ]]; then
    APPIMAGE_FLAGS+=("--appimage-extract-and-run")
fi
APPIMAGE_FLAGS+=("--no-sandbox" "--disable-setuid-sandbox" "--disable-gpu" "--disable-dev-shm-usage")


# Build runtime netfilter rules (combining public template with gitignored private overrides)
RUNTIME_NET="${SCRIPT_DIR}/.hermes-desktop-runtime.net"
LOCAL_NET="${SCRIPT_DIR}/hermes-desktop.net.local"
BASE_NET="${SCRIPT_DIR}/hermes-desktop.net"

NETFILTER_FLAGS=()
if [ -f "${BASE_NET}" ]; then
    if [ -f "${LOCAL_NET}" ]; then
        awk '
            /^-A OUTPUT -j REJECT/ {
                while ((getline line < "'"${LOCAL_NET}"'") > 0) {
                    print line
                }
            }
            { print }
        ' "${BASE_NET}" > "${RUNTIME_NET}"
        NETFILTER_FLAGS+=("--netfilter=${RUNTIME_NET}")
    else
        NETFILTER_FLAGS+=("--netfilter=${BASE_NET}")
    fi
fi

if [ ! -f "${PROFILE}" ]; then
    echo "Warning: Firejail profile not found at ${PROFILE}"
    echo "Falling back to default firejail sandbox..."
    exec firejail "${NETFILTER_FLAGS[@]}" --private-tmp --noroot --caps.drop=all \
        --read-only="${HOME}" \
        --read-write="${HOME}/.hermes" \
        --blacklist="${HOME}/.ssh" \
        --blacklist="${HOME}/.gnupg" \
        --nodbus \
        "${APPIMAGE}" "${APPIMAGE_FLAGS[@]}" "$@"
else
    exec firejail "${NETFILTER_FLAGS[@]}" --profile="${PROFILE}" "${APPIMAGE}" "${APPIMAGE_FLAGS[@]}" "$@"
fi






