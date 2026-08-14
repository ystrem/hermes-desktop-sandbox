# Security Review — Hermes Desktop Sandbox

Date: 2026-08-14

This review covers the Firejail profile, netfilter rules, launcher wrapper, and install
script in this repository. Findings are ordered by severity.

## Summary

The sandbox model is sound: all capabilities are dropped, `noroot` and `seccomp` are
enabled, the home directory is read-only with explicit whitelists, `/tmp` is private, and
sensitive paths are blacklisted. The main gaps are not in what is written, but in what is
**missing** — specifically X11 isolation, `/dev/input`, unix-socket escape paths, and a
likely-broken `INPUT` chain in the netfilter rules.

## Critical

- **X11 is shared with the host — keylogger + screen capture.**

  The profile only passes `env DISPLAY=${DISPLAY}` and has no `x11` directive. If the
  Electron renderer is compromised, it can read input from **all** windows, screenshot the
  screen, and inject fake input. X11 provides no isolation between clients.

  Fix: `x11 xorg` (Xephyr, requires `xorg-xephyr`) or use native Wayland
  (`env WAYLAND_DISPLAY` without XWayland). This is the largest real gap for a desktop
  sandbox.

- **Netfilter `-A INPUT -j DROP` with no `ESTABLISHED` accept.**

  The file only allows replies on the `OUTPUT` chain, but inbound packets (DNS replies,
  HTTP replies, even loopback to the 127.0.0.1 gateway) traverse `INPUT` and hit `DROP`.
  This either breaks networking entirely or relies on internal Firejail rules that are not
  guaranteed. Add explicitly:

  ```
  -A INPUT -i lo -j ACCEPT
  -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ```

- **Unix-socket escape → Docker/Podman/containerd socket.**

  `protocol unix` allows unix sockets, and netfilter only filters inet/inet6. The profile
  blocks `${HOME}/.docker` but not `/var/run/docker.sock`, `/run/docker.sock`,
  `/run/podman/podman.sock`, or `/run/containerd/containerd.sock`. If the user is in the
  `docker` group, the sandboxed app can gain root on the host through the socket. Blacklist
  these paths.

## High

- **Missing `private-dev` — access to `/dev/input`.**

  Without it, the sandbox has access to `/dev/input/event*` (keylogging) via the active
  seat's logind ACL. `nodvd`/`nou2f`/`no3d` do not block input devices. Add `private-dev`
  plus `noblacklist /dev/snd` (for the microphone). `private-dev` also covers `/dev/kmsg`,
  `/dev/mem`, etc.

- **D-Bus left open.**

  `nodbus` and `nodbus-user` are commented out for PulseAudio/PipeWire, so the app can call
  any session/system D-Bus service (screenshot, keyring, notifications). Consider
  `dbus-user none` / `dbus-system none` and verify audio still works over the raw socket
  (PipeWire supports `PIPEWIRE_RUNTIME_DIR`). At minimum document this as a conscious
  trade-off.

## Medium

- **`read-only ${HOME}` does not prevent exec.** Add `noexec ${HOME}` — the AppImage is
  mounted via FUSE into a private `/tmp`, so it is unaffected, but it blocks executing
  anything downloaded into the home directory.
- **Missing `restrict-namespaces`.** Without it the app can create new user namespaces.
  Caution: Electron/Chromium may need them for its own sandbox — if so, use the SUID
  chrome-sandbox instead of user namespaces and keep `restrict-namespaces`.
- **Weak fallback in the wrapper.** When the profile is missing, `run-hermes-desktop.sh`
  runs only `--private-tmp --noroot --caps.drop=all --read-only` with no `seccomp`,
  netfilter, or `private-dev`. It should either fail loudly or use the same strict profile.
- **`seccomp` without exceptions.** Electron/Chromium (JIT, GPU) may fail under the default
  seccomp filter. Verify functionality; if needed add `seccomp.keep` for the required
  syscalls.
- **Missing IPv6 ICMP.** `-p icmp` does not cover `ipv6-icmp` (IPv6 path MTU discovery).
  Minor.

## Low / cosmetic

- `blacklist ${HOME}/.docker/config.json` is redundant (the parent `${HOME}/.docker` is
  already blocked).
- `nodvd`/`notv`/`nocpu` are fine but contribute little compared to `private-dev`.
- Consider adding `blacklist /boot`, `blacklist /root`, or `private-etc` for a cleaner
  `/etc`.

## Context

This sandbox wraps an agent that is **intentionally** given full terminal and filesystem
access. Firejail therefore mainly protects against exploitation of the Electron/Chromium
renderer (XSS, JS exploits), not against what the agent does on instruction (prompt
injection). The highest-value fixes are X11 isolation, `/dev/input`, D-Bus, and socket
escape paths — the vectors through which a compromised renderer escapes or spies on the
rest of the desktop.

## Recommended next steps

1. Fix the netfilter `INPUT` chain.
2. Add `private-dev` + `noblacklist /dev/snd`.
3. Add X11 isolation (`x11 xorg`) or native Wayland.
4. Blacklist runtime sockets (docker/podman/containerd).
5. Reconsider D-Bus exposure.
