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

## Quick start (Portable / 100% Self-Contained)

```bash
# Install Firejail (Arch/CachyOS)
sudo pacman -S firejail

# Clone and run directly from the repo folder (no installation required!)
git clone https://github.com/ystrem/hermes-desktop-sandbox
cd hermes-desktop-sandbox

# Run directly inside the repo:
./run-hermes-desktop.sh
```


## Features

- **Automated CI/CD Builds**: GitHub Actions automatically monitors upstream `NousResearch/hermes-agent` for new releases every 6 hours, compiles the Linux AppImage on GitHub runners, and publishes GitHub Releases.
- **One-Click Auto-Updates**: Run `hermes-desktop-sandbox --update` to fetch and update to the latest pre-built AppImage automatically without local compilation.
- **Desktop Menu Entry**: Automatically creates `~/.local/share/applications/hermes-desktop-sandbox.desktop` for GNOME, KDE, Rofi, etc.
- **CLI Argument Forwarding**: Pass flags directly to the AppImage (e.g. `hermes-desktop-sandbox --devtools`).
- **Flexible Binary Discovery**: Auto-detects downloaded releases, `.AppImage` packages, unpacked executables (`linux-unpacked/hermes-desktop`), or honors `HERMES_APPIMAGE`.
- **Easy Uninstall**: Run `bash install.sh --uninstall` to remove installed profiles and launchers.

## Network isolation

> **How this actually behaves (read this first).** Firejail applies the
> `hermes-desktop.net` rules **only when the sandbox has its own network namespace**.
> This profile does not create one by default, so as shipped the netfilter chain —
> including its default-deny — is **inactive**. Opt into the strict, filtered path with
> `HERMES_SANDBOX_NETNS=1` (this runs Firejail with `--net=default`). Verify connectivity
> on your host before making it the default: joining a fresh netns can break loopback on
> some setups. See `SECURITY-REVIEW.md` (High → "Netfilter rules silently no-op").

When a namespace **is** active, Hermes can talk to:

- `localhost` (127.0.0.1) — the local Hermes gateway
- DNS (name resolution) and ICMP (path-MTU discovery)
- **Whitelisted destinations** — see below

### Whitelisting destinations

**Remote backend (recommended way)** — pass the backend at launch time; the launcher
injects an `ACCEPT` for each entry just above the default-deny:

```bash
HERMES_REMOTE_HOSTS="192.168.10.40" ./run-hermes-desktop.sh
# hostnames work too (resolved via DNS), and you can pass several, space- or comma-separated:
HERMES_REMOTE_HOSTS="hermes.lan,api.deepseek.com" ./run-hermes-desktop.sh
```

`HERMES_REMOTE_IPS` is accepted as an alias. For anything more permanent, add raw rules to
the gitignored `~/.config/firejail/hermes-desktop.net.local` — they are appended to the same
injection point:

```
-A OUTPUT -d 192.168.1.100/32 -j ACCEPT
-A OUTPUT -d api.deepseek.com -j ACCEPT
```

Rules are processed top to bottom, so **every `ACCEPT` must precede the final
`-A OUTPUT -j REJECT` / `-A INPUT -j DROP`**. The injection happens automatically at that
anchor, so you do not need to worry about ordering yourself.

## Environment Variables & Configuration

All paths and repository parameters are fully configurable via environment variables:

| Variable | Purpose | Default Value |
|----------|---------|---------------|
| `HERMES_SANDBOX_REPO` | GitHub repository (`owner/repo`) for releases | Auto-detected from `git remote` (or default fallback) |
| `HERMES_APPIMAGE` | Path to explicit AppImage or executable | Auto-detected in bin/release directories |
| `HERMES_PROFILE_DIR` | Firejail profiles directory | `${HOME}/.config/firejail` |
| `HERMES_BIN_DIR` | Executable launcher bin directory | `${HOME}/.local/bin` |
| `HERMES_DESKTOP_DIR` | XDG desktop entries directory | `${HOME}/.local/share/applications` |
| `HERMES_REMOTE_HOSTS` | Host/IP(s) of a remote Hermes backend to whitelist in the netfilter rules (space- or comma-separated; `HERMES_REMOTE_IPS` is an alias) | (empty) |
| `HERMES_SANDBOX_NETNS` | `1` runs Firejail with `--net=default` so the netfilter rules actually apply (strict network isolation). Verify on your host first. | `0` (off) |


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


