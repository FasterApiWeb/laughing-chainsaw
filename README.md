# LibreRing

<p align="center">
  <img src="docs/assets/logo.svg" alt="LibreRing logo" width="80" height="80">
</p>

<p align="center">
  <strong>Your body. Your data. No subscription.</strong>
</p>

<p align="center">
  <a href="https://github.com/FasterApiWeb/laughing-chainsaw/actions/workflows/ci.yml"><img src="https://github.com/FasterApiWeb/laughing-chainsaw/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/FasterApiWeb/laughing-chainsaw/actions/workflows/deploy-pages.yml"><img src="https://github.com/FasterApiWeb/laughing-chainsaw/actions/workflows/deploy-pages.yml/badge.svg" alt="Deploy Pages"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License"></a>
  <a href="https://fasterapiweb.github.io/laughing-chainsaw/docs/"><img src="https://img.shields.io/badge/docs-MkDocs Material-blue" alt="Documentation"></a>
  <a href="https://fasterapiweb.github.io/laughing-chainsaw/"><img src="https://img.shields.io/badge/demo-GitHub%20Pages-purple" alt="Live Demo"></a>
</p>

<p align="center">
  <a href="https://fasterapiweb.github.io/laughing-chainsaw/docs/">Documentation</a> ·
  <a href="https://fasterapiweb.github.io/laughing-chainsaw/">Web Dashboard</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="SECURITY.md">Security</a>
</p>

---

Open-source Oura Ring client. Connects over **Bluetooth LE**, stores data **locally**, writes to **Apple Health**, and optionally syncs to **your own Supabase** — no Oura subscription required.

Inspired by [LibrePods](https://github.com/nicklama/librepods).

## Highlights

| | |
|---|---|
| **Direct BLE** | Oura Ring 3/4/5 without the official app |
| **Offline-first** | SQLite / IndexedDB — cloud is optional |
| **Open algorithms** | Sleep, readiness, HRV scoring you can inspect |
| **Hybrid cloud** | Supabase Postgres + Cloudflare R2 (your keys) |
| **RE toolkit** | Python CLIs for protocol research |

## Live links

| Resource | URL |
|----------|-----|
| **Documentation** | https://fasterapiweb.github.io/laughing-chainsaw/docs/ |
| **Web dashboard** | https://fasterapiweb.github.io/laughing-chainsaw/ |
| **Releases** | https://github.com/FasterApiWeb/laughing-chainsaw/releases |

## Monorepo structure

```
apps/web              Next.js dashboard (GitHub Pages)
apps/ios              Swift/SwiftUI + CoreBluetooth + HealthKit
apps/android          Kotlin/Compose scaffold
packages/sdk-ts       @librering/sdk
packages/api-spec     OpenAPI contract
backend/supabase      Postgres schema, RLS, sync RPCs
backend/worker        Cloudflare Worker → R2
core/librering-core   Rust BLE protocol
tools/                Python reverse-engineering toolkit
docs/                 MkDocs documentation source
```

## Quick start

### Web dashboard

```bash
pnpm install
cp apps/web/.env.example apps/web/.env.local   # optional Supabase
pnpm dev:web
```

### iOS app

```bash
cd apps/ios/LibreRing
brew install xcodegen && xcodegen generate
open LibreRing.xcodeproj   # run on physical iPhone
```

### Documentation (local)

```bash
pip install -r docs/requirements.txt
pnpm docs:serve    # http://127.0.0.1:8000
```

### Python RE toolkit

```bash
cd tools && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python scan_oura.py --read-values
```

## Documentation

| Guide | Description |
|-------|-------------|
| [Concepts](docs/concepts.md) | Design principles & sync model |
| [Architecture](docs/ARCHITECTURE.md) | System design |
| [Cloud Setup](docs/SETUP_CLOUD.md) | Supabase + optional R2 |
| [Deploy](docs/DEPLOY.md) | GitHub Pages |
| [Contributing](CONTRIBUTING.md) | PR guidelines |
| [Open Source Checklist](docs/OPEN_SOURCE.md) | OSS readiness |
| [Protocol](PROTOCOL.md) | BLE specification |

Full site: **https://fasterapiweb.github.io/laughing-chainsaw/docs/**

## Roadmap

- [x] BLE protocol reverse engineering
- [x] iOS app + HealthKit
- [x] Web dashboard + cloud sync
- [x] Monorepo + Supabase/R2 backend
- [x] MkDocs + CI/CD
- [ ] Background sync (BGTaskScheduler)
- [ ] Android + Health Connect
- [ ] Rust core UniFFI on mobile
- [ ] PyPI / crates.io packages

## Security & privacy

Never commit ring auth keys or health captures:

| Path | Contents |
|------|----------|
| `key.hex` | 16-byte BLE auth key |
| `tools/services.json` | GATT dump |
| `tools/captures/` | Session logs |

Report vulnerabilities via [SECURITY.md](SECURITY.md) (private advisory).

## Legal

Clean-room reverse engineering for interoperability. Not affiliated with Oura Health Oy. See [docs/legal.md](docs/legal.md).

## License

[MIT](LICENSE) — Copyright (c) 2026 FasterApiWeb
