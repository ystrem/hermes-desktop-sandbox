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
    echo "  HERMES_APPIMAGE           Path to custom Hermes AppImage or executable"
    echo "  HERMES_SKIP_UPDATE_CHECK  Set to 1 to skip the startup check for a newer release"
    echo ""
    echo "On startup (interactive terminal) the installed version is compared with the newest"
    echo "GitHub release and you are asked whether to update."
    echo ""
    echo "Options:"
    echo "  --update, --download   Download / update to the latest pre-built release without asking"
    echo "  -h, --help             Show this help message and exit"
    echo ""
    exit 0
}

APP_DIR="${DOWNLOAD_DIR}/hermes-desktop-app"
# Records "<version> <release-tag>" of the currently installed build (gitignored)
INSTALLED_MARKER="${DOWNLOAD_DIR}/.hermes-installed-release"

# Print the path of the first executable found in a directory (name differs between builds)
find_binary() {
    local dir="$1" name
    for name in hermes-desktop Hermes hermes AppRun; do
        if [ -f "${dir}/${name}" ] && [ -x "${dir}/${name}" ]; then
            echo "${dir}/${name}"
            return 0
        fi
    done
    return 1
}

# Find the newest non-draft release that has a downloadable .tar.gz (preferred) or .AppImage.
# Sets REL_TAG, REL_FILE, REL_URL, REL_VER. Returns 1 if nothing usable was found.
fetch_latest_release() {
    local max_time="${1:-15}" json pick
    json=$(curl -sS --connect-timeout 5 -m "${max_time}" -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${RELEASE_REPO}/releases?per_page=30" 2>/dev/null) || return 1
    echo "${json}" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1

    pick=$(echo "${json}" | jq -r '
        [ .[] | select(.draft == false) | . as $r
          | ( [ $r.assets[] | select(.name | endswith(".tar.gz")) ][0]
              // [ $r.assets[] | select(.name | endswith(".AppImage")) ][0] ) as $a
          | select($a != null)
          | [ $r.tag_name, $a.name, $a.browser_download_url ] ]
        | .[0] // empty | @tsv') || return 1
    [ -n "${pick}" ] || return 1

    IFS=$'\t' read -r REL_TAG REL_FILE REL_URL <<< "${pick}"
    REL_VER=$(echo "${REL_FILE}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
    return 0
}

download_latest_release() {
    echo "==> Fetching latest pre-built Hermes Desktop release from GitHub (${RELEASE_REPO})..."
    if ! fetch_latest_release 30; then
        echo "Error: No release with a downloadable .tar.gz or .AppImage found in ${RELEASE_REPO}."
        echo "Ensure the repository is public and GitHub Actions has published a release with files attached."
        return 1
    fi

    mkdir -p "${DOWNLOAD_DIR}"
    local target_path="${DOWNLOAD_DIR}/${REL_FILE}"

    echo "==> Downloading ${REL_FILE} (${REL_TAG}) to ${DOWNLOAD_DIR}..."
    if ! curl -fL --progress-bar -o "${target_path}" "${REL_URL}"; then
        echo "Error: Download failed."
        return 1
    fi

    if [[ "${REL_FILE}" == *.tar.gz ]]; then
        local new_dir="${APP_DIR}.new" bin
        echo "==> Extracting native Linux package to ${APP_DIR}..."
        rm -rf "${new_dir}"
        mkdir -p "${new_dir}"
        if ! tar -xzf "${target_path}" -C "${new_dir}"; then
            echo "Error: Extraction failed."
            rm -rf "${new_dir}"
            return 1
        fi
        if ! bin=$(find_binary "${new_dir}"); then
            echo "Error: No executable (hermes-desktop / Hermes / AppRun) found in ${REL_FILE}."
            rm -rf "${new_dir}"
            return 1
        fi
        # Swap in the new version only after it was extracted and verified
        rm -rf "${APP_DIR}.prev"
        if [ -d "${APP_DIR}" ]; then
            mv "${APP_DIR}" "${APP_DIR}.prev"
        fi
        mv "${new_dir}" "${APP_DIR}"
        rm -rf "${APP_DIR}.prev"
        APPIMAGE="${APP_DIR}/$(basename "${bin}")"
    else
        chmod +x "${target_path}"
        APPIMAGE="${target_path}"
        # Force re-extraction of the new AppImage on next step
        rm -rf "${APP_DIR}"
    fi

    echo "${REL_VER} ${REL_TAG}" > "${INSTALLED_MARKER}"
    echo "  ✓ Download and extraction complete: ${APPIMAGE} (${REL_VER})"
}

# At startup: compare installed version with the newest release and ask whether to update.
# Silent when offline, non-interactive, or already up to date.
check_for_update() {
    if [ ! -t 0 ] || [ ! -t 1 ] || [ "${HERMES_SKIP_UPDATE_CHECK:-0}" = "1" ]; then
        return 0
    fi
    fetch_latest_release 8 || return 0
    [ -n "${REL_VER}" ] || return 0

    local installed_ver="" installed_tag="" newer=0
    if [ -f "${INSTALLED_MARKER}" ]; then
        read -r installed_ver installed_tag < "${INSTALLED_MARKER}" || true
    fi

    if [ -z "${installed_ver}" ]; then
        newer=1
    elif [ "${REL_VER}" != "${installed_ver}" ] && \
         [ "$(printf '%s\n%s\n' "${installed_ver}" "${REL_VER}" | sort -V | tail -n 1)" = "${REL_VER}" ]; then
        newer=1
    fi
    [ "${newer}" = "1" ] || return 0

    echo "💡 Nová verze Hermes Desktop: ${REL_VER} (${REL_TAG})"
    echo "   Nainstalováno: ${installed_ver:-neznámá verze}"
    local answer=""
    read -r -p "   Aktualizovat teď? [a/N] " answer || true
    case "${answer}" in
        [aAyY]*)
            if ! download_latest_release; then
                echo "⚠ Aktualizace selhala, spouštím stávající verzi."
            fi
            ;;
    esac
    return 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
fi

if [[ "${1:-}" == "--update" || "${1:-}" == "--download" ]]; then
    download_latest_release || exit 1
    HERMES_SKIP_UPDATE_CHECK=1
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
                # Check for direct native binary (hermes-desktop / Hermes / AppRun)
                if FOUND=$(find_binary "${dir}"); then
                    APPIMAGE="${FOUND}"
                    break
                fi
                if FOUND=$(find_binary "${dir}/linux-unpacked"); then
                    APPIMAGE="${FOUND}"
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

# If still not found, download automatically
if [ -z "${APPIMAGE}" ]; then
    echo "No local Hermes executable or package found."
    echo "Attempting automatic download of pre-built release from GitHub..."
    download_latest_release || exit 1
else
    # Check for a newer release and ask whether to update (interactive terminals only)
    check_for_update
fi

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


# Build runtime netfilter rules: the public template plus destination ACCEPTs
# from HERMES_REMOTE_HOSTS / HERMES_REMOTE_IPS (env) and the gitignored
# hermes-desktop.net.local, all injected just above the `-A OUTPUT -j REJECT`
# default-deny anchor so the template stays machine-independent.
RUNTIME_NET="${SCRIPT_DIR}/.hermes-desktop-runtime.net"
LOCAL_NET="${SCRIPT_DIR}/hermes-desktop.net.local"
BASE_NET="${SCRIPT_DIR}/hermes-desktop.net"

NETFILTER_FLAGS=()
if [ -f "${BASE_NET}" ]; then
    # A remote Hermes backend must be reachable. Pass it either as a bare IP or
    # a hostname (resolved by Firejail's DNS), space- or comma-separated:
    #   HERMES_REMOTE_HOSTS="192.168.10.40 hermes.lan" ./run-hermes-desktop.sh
    INJECT_TMP="$(mktemp)"
    for entry in ${HERMES_REMOTE_HOSTS:-} ${HERMES_REMOTE_IPS:-}; do
        for dest in ${entry//,/ }; do
            echo "-A OUTPUT -d ${dest} -j ACCEPT" >> "${INJECT_TMP}"
        done
    done
    if [ -f "${LOCAL_NET}" ]; then
        cat "${LOCAL_NET}" >> "${INJECT_TMP}"
    fi
    awk -v inject="${INJECT_TMP}" '
        /^-A OUTPUT -j REJECT/ {
            while ((getline line < inject) > 0) {
                if (line != "") print line
            }
        }
        { print }
    ' "${BASE_NET}" > "${RUNTIME_NET}"
    rm -f "${INJECT_TMP}"
    NETFILTER_FLAGS+=("--netfilter=${RUNTIME_NET}")
fi

# Firejail only enforces netfilter rules when the sandbox has its own network
# namespace. Without one the rules above (and the default deny) are ignored and
# the sandbox applies NO network restriction. Opt in to the strict path with:
#   HERMES_SANDBOX_NETNS=1
if [ "${HERMES_SANDBOX_NETNS:-0}" = "1" ]; then
    NETFILTER_FLAGS+=("--net=default")
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






