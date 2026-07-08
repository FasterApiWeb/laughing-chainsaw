# LibreRing

**Your body. Your data. No subscription.**

LibreRing bypasses the Oura Ring subscription ($6/month) by connecting directly to your ring over Bluetooth, reading all sensor data locally, and syncing it to Apple Health. Optional cloud backup uses **Supabase + Cloudflare R2** — your keys, your Postgres, your blobs.

Inspired by [LibrePods](https://github.com/nicklama/librepods) — if they can unlock AirPods on Android, we can unlock Oura on your terms.

## What it does

- Connects to Oura Ring 3/4/5 via BLE without the Oura app
- Reads HR, HRV, SpO2, temperature, sleep stages, steps, accelerometer
- Computes sleep score, readiness score, and HRV analysis with **open algorithms**
- Writes everything to **Apple Health** automatically
- Stores data locally — export anytime as JSON/CSV
- **Optional** cloud sync across devices (Supabase Postgres + R2 exports)

## Monorepo structure

```
apps/
  web/              Next.js dashboard (GitHub Pages, IndexedDB)
  ios/              Swift/SwiftUI + CoreBluetooth + HealthKit
  android/          Kotlin/Compose scaffold
packages/
  sdk-ts/           @librering/sdk — auth, sync, storage client
  api-spec/         OpenAPI contract
backend/
  supabase/         Postgres schema, RLS, sync RPCs
  worker/           Cloudflare Worker → R2 presigned URLs
core/
  librering-core/   Rust BLE protocol (UniFFI for mobile)
tools/              Python reverse-engineering toolkit
docs/               Architecture, backend setup, contributing
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full system design.

## Quick start

### Web dashboard

```bash
pnpm install
cp apps/web/.env.example apps/web/.env.local   # optional Supabase keys
pnpm dev:web
```

### iOS app

```bash
cd apps/ios/LibreRing
brew install xcodegen
xcodegen generate
open LibreRing.xcodeproj
```

Build on a physical iPhone (BLE requires hardware).

### Python RE toolkit

```bash
cd tools
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python scan_oura.py --read-values
```

### Backend (optional cloud sync)

1. Apply `backend/supabase/migrations/*.sql` to your Supabase project
2. Deploy `backend/worker` to Cloudflare with R2 bucket
3. Set env vars in clients (see [docs/BACKEND.md](docs/BACKEND.md))

## Backend: why Supabase + R2?

We use **Supabase for auth and structured health data** and **Cloudflare R2 for large file storage** — not Supabase Storage alone and not Cloudflare-only.

| Component | Provider | Reason |
|-----------|----------|--------|
| Auth + Postgres | Supabase | RLS, mobile SDKs, fast DX |
| Blob exports | Cloudflare R2 | 10 GB free, cheap egress |
| Presigned URLs | CF Worker | JWT verify + R2 access |

Full comparison: [docs/BACKEND_COMPARISON.md](docs/BACKEND_COMPARISON.md)

## Contributing

Read [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) before opening a PR.

## Protocol references

- [PROTOCOL.md](PROTOCOL.md) — Oura BLE specification
- [ringverse/protocol](https://github.com/ringverse/protocol) — community docs
- [open_oura](https://github.com/Th0rgal/open_oura) — Rust CLI (MIT)

## Roadmap

- [x] BLE protocol reverse engineering
- [x] iOS app with CoreBluetooth + HealthKit
- [x] Web dashboard with local IndexedDB
- [x] Monorepo + Supabase/R2 backend scaffold (phases 1–5)
- [ ] Background sync (BGTaskScheduler)
- [ ] Android + Health Connect
- [ ] Rust core UniFFI bindings on iOS/Android
- [ ] PyPI package for protocol library

## Deploy (GitHub Pages)

See [docs/DEPLOY.md](docs/DEPLOY.md) for one-time GitHub + Supabase URL setup, then push to `main`.

Production: https://fasterapiweb.github.io/laughing-chainsaw/

## Personal data (gitignored)

Never commit ring auth keys, GATT dumps, or health captures:

| Path | Contents |
|------|----------|
| `key.hex` | 16-byte BLE auth key |
| `tools/services.json` | GATT dump |
| `tools/captures/` | probe/listen logs |

Use `key.hex.example` as a template.

## Legal

Clean-room reverse engineering under DMCA §1201(f) for interoperability. LibreRing does not distribute proprietary code, modify firmware, or bypass DRM.

## License

MIT
