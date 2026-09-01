# Hermes Desktop Sandbox

Firejail sandbox profile for isolating the [Hermes Agent](https://hermes-agent.nousresearch.com) desktop app — an Electron application that runs a personal AI agent with full filesystem and terminal access.

## Why sandbox the Hermes desktop?

The Hermes desktop app is an **Electron shell** (Chromium + Node.js) with access to:

- Your `~/.hermes/` config (API keys, tokens, sessions)
- Terminal execution via the integrated TTY
- Browser automation (Playwright/Chromium)
- Filesystem read/write via the agent's tools

Sandboxing with Firejail restricts:

- **Filesystem** — only `~/.hermes/` and Electron app config writable, everything else blocked
- **Network** — only localhost + whitelisted local/remote IPs
- **Capabilities** — none
- **Temp** — isolated `/tmp`
- **Sensitive data** — SSH keys, GPG, cloud credentials (AWS/GCP/Azure/Kube), password vaults, browser histories hidden

## What's in here

| File | Purpose |
|------|---------|
| `hermes-desktop.local` | Firejail profile — sandbox rules |
| `hermes-desktop.net` | Netfilter rules — restrict to specific IPs/domains |
| `run-hermes-desktop.sh` | Wrapper script to launch the sandboxed desktop & check for updates |
| `install.sh` | Setup script (copies profiles, launcher, desktop entry, auto-downloads release) |
| `.github/workflows/build-desktop.yml` | Automated GitHub Actions workflow building AppImages on upstream updates |

## Quick start

```bash
# Install Firejail (Arch/CachyOS)
sudo pacman -S firejail

# Clone and install
git clone https://github.com/ystrem/hermes-desktop-sandbox
cd hermes-desktop-sandbox
bash install.sh

# EDIT the netfilter rules before first run:
vim ~/.config/firejail/hermes-desktop.net
# → uncomment the line with your local IP (ai-worker, aicore, etc.)

# Launch sandboxed Hermes desktop from application menu or terminal:
hermes-desktop-sandbox
```

## Features

- **Automated CI/CD Builds**: GitHub Actions automatically monitors upstream `NousResearch/hermes-agent` for new releases every 6 hours, compiles the Linux AppImage on GitHub runners, and publishes GitHub Releases.
- **One-Click Auto-Updates**: Run `hermes-desktop-sandbox --update` to fetch and update to the latest pre-built AppImage automatically without local compilation.
- **Desktop Menu Entry**: Automatically creates `~/.local/share/applications/hermes-desktop-sandbox.desktop` for GNOME, KDE, Rofi, etc.
- **CLI Argument Forwarding**: Pass flags directly to the AppImage (e.g. `hermes-desktop-sandbox --devtools`).
- **Flexible Binary Discovery**: Auto-detects downloaded releases, `.AppImage` packages, unpacked executables (`linux-unpacked/hermes-desktop`), or honors `HERMES_APPIMAGE`.
- **Easy Uninstall**: Run `bash install.sh --uninstall` to remove installed profiles and launchers.

## Network isolation

By default, Hermes can **only** talk to:

- `localhost` (127.0.0.1) — the local Hermes gateway
- DNS (for name resolution)
- **Whitelisted IPs/hosts** specified in `hermes-desktop.net`

To whitelist your local worker or API endpoints, edit `~/.config/firejail/hermes-desktop.net` and uncomment/add rules:
```
-A OUTPUT -d 192.168.10.194/32 -j ACCEPT
-A OUTPUT -d api.deepseek.com -j ACCEPT
```

*Note:* For Firejail netfilter rules to take effect, Firejail requires an active network namespace. You can pass `--net=default` or uncomment `net default` in `hermes-desktop.local`.

## Microphone (dictation)

Microphone works — the profile preserves:

- PulseAudio/PipeWire sockets
- ALSA config
- `/dev/snd` access

No extra configuration needed. If audio stops working, check that `nogroups` is **not** set (it's commented out by default).

## What gets restricted

| Area | Restriction |
|------|-------------|
| SSH keys | Blocked (`~/.ssh`) |
| GPG keys | Blocked (`~/.gnupg`) |
| Cloud credentials | Blocked (`~/.aws`, `~/.azure`, `~/.kube`, `~/.config/gcloud`) |
| Password stores | Blocked (`~/.password-store`, `~/.config/Bitwarden`, `~/.config/1Password`, `~/.config/KeePassXC`) |
| Browser data | Blocked (Chromium, Chrome, Brave, Edge, Firefox, Opera, Vivaldi) |
| Developer tokens | Blocked (`~/.npmrc`, `~/.pypirc`, `~/.cargo/credentials*`, `~/.config/gh`) |
| Shell config & history | Blocked (`~/.bash_history`, `~/.zsh_history`, `~/.fish_history`, `~/.python_history`) |
| /tmp | Private (binds to new empty tmpfs) |
| Network | Only 127.0.0.1 + whitelisted IPs |
| Kernel | No new privileges, seccomp |
| Capabilities | All dropped |

## Building locally (Optional)

If you prefer building locally instead of downloading pre-built releases:

```bash
cd ~/.hermes/hermes-agent/apps/desktop
npm run pack    # produces Hermes-*.AppImage and linux-unpacked/ in release/
```

The launcher script auto-detects local AppImages or unpacked binaries.


