# Contributing to LibreRing

Thank you for helping build open, subscription-free Oura access.

## Quick start

```bash
git clone https://github.com/FasterApiWeb/laughing-chainsaw.git
cd laughing-chainsaw
pnpm install

# Web dashboard
pnpm dev:web

# Python RE tools
cd tools && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

Read [ARCHITECTURE.md](./ARCHITECTURE.md) first — it explains how apps, backend, and `tools/` relate.

## Repository layout

| Path | Purpose |
|------|---------|
| `apps/web` | Static health dashboard |
| `apps/ios` | iOS app |
| `apps/android` | Android scaffold |
| `packages/sdk-ts` | Shared TypeScript client |
| `packages/api-spec` | OpenAPI contract |
| `backend/supabase` | SQL migrations |
| `backend/worker` | Cloudflare Worker |
| `core/librering-core` | Rust protocol |
| `tools/` | Python BLE research CLIs |
| `docs/` | Architecture and setup |

## Code standards

### General

- **Minimal diffs** — fix one thing per PR when possible
- **Offline-first** — never require cloud for core features
- **No secrets** — `key.hex`, `.env`, captures stay gitignored

### SOLID (by language)

| Language | Interfaces | Implementations |
|----------|------------|-----------------|
| TypeScript | `AuthService`, `SyncService`, `StorageService` | `Supabase*`, `Worker*` |
| Swift | `SyncRepository` | `SupabaseSyncRepository` |
| Kotlin | `SyncRepository` | `SupabaseSyncRepository` |
| Rust | pure functions + `ProtocolError` | no hidden global state |

### Naming

- RPCs: `snake_case` in Postgres, `camelCase` in TS clients
- Tables: match local schema names (`heart_rate`, not `heartRate`)
- Packages: `@librering/*` scope

## Making changes

### Database / API

1. Edit SQL in `backend/supabase/migrations/` (new numbered file)
2. Update `packages/api-spec/openapi.yaml`
3. Update `packages/sdk-ts` if types change
4. Document in `docs/BACKEND.md`

### Web UI

1. Components in `apps/web/src/components/`
2. Data layer in `apps/web/src/lib/`
3. Run `pnpm lint:web` and `pnpm build:web`

### iOS

1. Edit Swift under `apps/ios/LibreRing/LibreRing/`
2. Run `xcodegen generate` if `project.yml` changes
3. Test on device (BLE)

### Rust core

1. Add tests in `core/librering-core/src/`
2. Keep in sync with `tools/oura_protocol.py` and `PROTOCOL.md`

## Pull requests

- Describe **why**, not just what
- Include test plan (device, browser, or `cargo test`)
- Do not commit personal captures or `key.hex`

## Sensitive data

See root `README.md` — never commit ring auth keys, GATT dumps, or health JSONL logs.

## Questions

Open a GitHub issue with the `question` label or check existing docs in `docs/`.
