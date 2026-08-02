# PVE Pilot (pve-pilot)

> [简体中文](README.md) · A Proxmox VE remote management app for fnOS (feiniu OS)

> ⚡ **Vibe Coding project**: built with AI coding agents (Codex CLI); humans own architecture decisions and code review.

Access your Proxmox VE WebUI through the FN Connect tunnel — **no public IP required**. V1 (MVP) provides full passthrough of the original PC WebUI.

PVE Pilot ships a built-in static nginx reverse-proxy engine (~5–8MB, no management UI). Fill in your PVE address in the native fnOS setup wizard and you get a reachable link.

## Features (V1)

- **Zero-config**: install from the app center, enter the PVE address/port, done
- **Full passthrough** of the original PVE WebUI (root path), preserving PVE's own authentication (password / 2FA) — no PVE credentials are ever stored
- **FN Connect tunnel** via the declared service port (`pvepilot.sc`)
- **Built-in static nginx** (`http_proxy` / `http_ssl` / `stream`), no external deps
- **Configuration-only app**: no custom daemon; lifecycle managed by fnOS

## Layout

```
pve-pilot/
├── fnos/            # fnOS app (manifest / wizard / lifecycle scripts / icons)
├── build/           # static nginx build + .fpk packaging + local verification
├── docs/            # design docs (00-04)
└── tasks/           # task book
```

## Build & package

```bash
./build/build-nginx.sh --arch both     # static nginx for x86_64 + aarch64
python3 build/gen-icons.py             # regenerate icons if needed
./build/package.sh --arch both         # build/dist/pvepilot_<version>_<arch>.fpk
```

Requirements: `gcc`, `gcc-aarch64-linux-gnu` (arm cross), `curl`, `tar`, `patch`.
OpenSSL is compiled from source (3.6.x LTS by default), nginx defaults to the 1.28.x stable series; both can be overridden via environment variables.

## Local verification

```bash
./build/test/local-verify.sh
```

It simulates the fnOS lifecycle environment, checks every proxy directive, runs `nginx -t`, and does an end-to-end passthrough test against a local self-signed HTTPS backend (Host header forwarding, config rewrite + restart, start/stop/restart/status/log).

## Usage

1. Install the `.fpk` from `build/dist/` via the fnOS app center ("manual install")
2. Enter in the wizard: PVE address, PVE port (default 8006), proxy port (default 8800)
3. Open the app — or browse to `http://<your-nas>:8800` / your FN Connect link — and you'll see the original PVE WebUI

> Keep the proxy port at 8800: it matches the port-forward declaration in the `.sc` file used by FN Connect. Changing it affects local access only (tunnel forwarding still follows the `.sc` declaration) — pending real-device testing.

## Design constraints (do not change)

1. Root-path passthrough only (PVE hardcodes the root path; subdirectory 404s)
2. The `Host` header must be passed through (PVE builds URLs from it)
3. `proxy_ssl_verify off` (PVE's 8006 is self-signed HTTPS; the browser→NAS segment is secured by the FN Connect `fnos.net` certificate)

See [docs/04-设计.md](docs/04-设计.md) and `tasks/v1-codex.md` for details.

## License

MIT © 2026 pve-pilot
