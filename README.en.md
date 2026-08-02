# PVE Pilot (pve-pilot)

> [简体中文](README.md) · A Proxmox VE remote management app for fnOS (feiniu OS)

> ⚡ **Vibe Coding project**: built with AI coding agents (Codex CLI); humans own architecture decisions and code review.

Access your Proxmox VE WebUI through the FN Connect tunnel — **no public IP required**. PVE Pilot brings the Proxmox VE WebUI into the fnOS app store: one link, remote management.

## Features

- **Zero-config**: install from the app center, enter the PVE address/port, done
- **Full passthrough** of the original PVE WebUI — identical to local use, preserving PVE's own authentication (password / 2FA). No PVE credentials are ever stored
- **FN Connect tunnel**: remote management without a public IP
- **Automatic mobile UI**: phones automatically get PVE's official mobile interface — **PVE 9.0+** ships a brand-new Rust/Yew (WASM) UI (bottom tabs: Dashboard/Resources/Configuration); **PVE 8.x** uses the legacy Sencha Touch mobile UI; non-mobile user agents get the desktop WebUI
- **Lightweight built-in engine**: static nginx reverse proxy (~5–8MB), zero external dependencies
- **Secure & transparent**: login, permissions and 2FA all stay with PVE itself; the app never touches your credentials

## Roadmap

- **V1 (MVP, in progress)**: access the original PVE WebUI from PC (full passthrough)
- **V2 (planned)**: mobile enhancements — PVE 9.0+ already ships an official mobile UI (auto-switched for phones, no custom UI needed); evaluate extras like a noVNC console
- **V3 (future)**: snapshots & backups, multi-node clusters, notifications

## Usage

1. Install the app from the fnOS app center
2. In the setup wizard, enter: **PVE address** (IP or hostname), **PVE port** (default 8006), **proxy port** (default 8006, changeable)
3. Open the app — or browse to `http://<your-nas>:8006` / your FN Connect link — and you'll see the original PVE WebUI. Phones automatically get PVE's official mobile UI (best experience on PVE 9.0+)

## License

MIT © 2026 pve-pilot
