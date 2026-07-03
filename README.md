# Hermes Desktop Sandbox

Firejail sandbox profile for isolating the [Hermes Agent](https://hermes-agent.nousresearch.com) desktop app — an Electron application that runs a personal AI agent with full filesystem and terminal access.

## Why sandbox the Hermes desktop?

The Hermes desktop app is an **Electron shell** (Chromium + Node.js) with access to:

- Your `~/.hermes/` config (API keys, tokens, sessions)
- Terminal execution via the integrated TTY
- Browser automation (Playwright/Chromium)
- Filesystem read/write via the agent's tools

Sandboxing with Firejail restricts:

- **Filesystem** — only `~/.hermes/` writable, everything else blocked
- **Network** — only localhost + one whitelisted local IP
- **Capabilities** — none
- **Temp** — isolated `/tmp`
- **Sensitive data** — SSH keys, GPG, vaults, shell histories hidden

## What's in here

| File | Purpose |
|------|---------|
| `hermes-desktop.local` | Firejail profile — sandbox rules |
| `hermes-desktop.net` | Netfilter rules — restrict to specific IPs |
| `run-hermes-desktop.sh` | Wrapper script to launch the sandboxed desktop |
| `install.sh` | One-shot setup (copies profiles, creates launcher) |

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

# Launch sandboxed Hermes desktop
hermes-desktop-sandbox
```

## Network isolation

By default, Hermes can **only** talk to:

- `localhost` (127.0.0.1) — the local Hermes gateway
- DNS (for name resolution)
- **One local IP** you whitelist in `hermes-desktop.net`

To whitelist your IP, edit `~/.config/firejail/hermes-desktop.net` and uncomment:
```
-A OUTPUT -d 192.168.10.194/32 -j ACCEPT
```

Everything else is dropped by `iptables`. If Hermes needs to reach external API providers directly (not proxied through local gateway), uncomment the relevant lines for `api.openai.com`, `api.anthropic.com`, etc.

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
| Password stores | Blocked (`~/.password-store`, `~/.config/Bitwarden`) |
| Browser data | Blocked (Chromium, Chrome, Brave, Edge) |
| Shell config | Blocked (`~/.bash_history`, `~/.zsh_history`) |
| /tmp | Private (binds to new empty tmpfs) |
| Network | Only 127.0.0.1 + whitelisted IP |
| Kernel | No new privileges, seccomp |
| Capabilities | All dropped |

## Building the desktop AppImage

```bash
cd ~/.hermes/hermes-agent/apps/desktop
npm run dist:linux    # produces Hermes-*.AppImage in release/
```

The wrapper script auto-detects the latest AppImage in the release directory.
