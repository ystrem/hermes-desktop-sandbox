# Hermes Desktop Sandbox

Firejail sandbox profile for isolating the [Hermes Agent](https://hermes-agent.nousresearch.com) desktop app — an Electron application that runs a personal AI agent with full filesystem and terminal access.

## Why sandbox the Hermes desktop?

The Hermes desktop app is an **Electron shell** (Chromium + Node.js) that has access to:

- Your `~/.hermes/` config (API keys, tokens, sessions)
- Terminal execution via the integrated TTY
- Browser automation (Playwright/Chromium)
- Filesystem read/write via the agent's tools

Sandboxing with Firejail restricts:

- **Filesystem** — Hermes can only read/write paths it actually needs
- **Capabilities** — no kernel privileges
- **Network** — limited to API providers and local gateway
- **Temp** — isolated `/tmp` to prevent /tmp race attacks
- **Devices** — no webcam/microphone unless explicitly needed

## What's in here

| File | Purpose |
|------|---------|
| `hermes-desktop.local` | Firejail profile — sandbox rules |
| `run-hermes-desktop.sh` | Wrapper script to launch the sandboxed desktop |
| `install.sh` | One-shot setup (copies profile, creates desktop entry) |

## Quick start

```bash
# Install Firejail (Arch/CachyOS)
sudo pacman -S firejail

# Run the setup
bash install.sh

# Launch sandboxed Hermes desktop
hermes-desktop-sandbox
```

Or manually:

```bash
# Build the desktop first (from hermes-agent repo)
cd ~/.hermes/hermes-agent/apps/desktop
npm run dist:linux

# Run it sandboxed
firejail --profile=hermes-desktop.local \
  ~/.hermes/hermes-agent/apps/desktop/release/Hermes-*.AppImage
```

## What gets restricted

| Area | Restriction |
|------|-------------|
| SSH keys | Blocked (`~/.ssh`) |
| GPG keys | Blocked (`~/.gnupg`) |
| Password stores | Blocked (`~/.config/Bitwarden`, `~/.config/chromium`) |
| Shell config | Blocked (`~/.bash_history`, `~/.zsh_history`) |
| /tmp | Private (binds to new empty tmpfs) |
| D-Bus | Blocked (no MPRIS, no desktop notifications) |
| Kernel | No new privileges, no realtime, no modules |
| Devices | No webcam, no audio capture |
| Network | Restricted to AF_UNIX, AF_INET, AF_INET6 only |
| Capabilities | All dropped |

## Allowed paths

Hermes needs write access to:

- `~/.hermes/` — config, sessions, logs, skills
- `~/.local/share/hermes/` — application data

Everything else in `$HOME` is read-only or blocked.

## Building the desktop AppImage

If you haven't built the desktop app yet:

```bash
cd ~/.hermes/hermes-agent/apps/desktop
npm run dist:linux    # produces Hermes-*.AppImage in release/
```

The wrapper script auto-detects the latest AppImage in the release directory.

## Notes

- Tested on Arch Linux / CachyOS with Firejail 0.9.72+
- Works on X11 and Wayland
- If you use audio capture (voice conversations), remove `nodbus` and `nogroups` from the profile and add `--net=ip` for the microphone socket
