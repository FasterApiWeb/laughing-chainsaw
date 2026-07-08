# LibreRing

**Your body. Your data. No subscription.**

LibreRing is an open-source alternative to the Oura subscription app. It connects directly to your Oura Ring over Bluetooth, stores health data locally, syncs to Apple Health, and optionally backs up to your own Supabase account.

[:octicons-rocket-24: Quick Start](SETUP_CLOUD.md){ .md-button .md-button--primary }
[:octicons-mark-github-16: GitHub](https://github.com/FasterApiWeb/laughing-chainsaw){ .md-button }
[:octicons-browser-24: Web Dashboard](https://fasterapiweb.github.io/laughing-chainsaw/){ .md-button }

---

## What you get

| Feature | iOS | Web | Android |
|---------|:---:|:---:|:-------:|
| Direct BLE to Oura Ring | ✅ | — | 🔜 |
| Local storage (offline-first) | ✅ | ✅ | 🔜 |
| Apple Health / Health Connect | ✅ | — | 🔜 |
| Sleep & readiness scoring | ✅ | ✅ | 🔜 |
| Optional cloud sync (Supabase) | 🔜 | ✅ | 🔜 |
| Oura export import | — | ✅ | — |

## Monorepo at a glance

```
apps/web          → Next.js dashboard (GitHub Pages)
apps/ios          → Swift/SwiftUI + CoreBluetooth + HealthKit
apps/android      → Kotlin scaffold
packages/sdk-ts   → @librering/sdk
backend/supabase  → Postgres + RLS + sync RPCs
backend/worker    → Cloudflare R2 presigned URLs
core/librering-core → Rust BLE protocol
tools/            → Python reverse-engineering CLIs
```

## Documentation map

- **[Concepts](concepts.md)** — design principles, sync model, legal basis
- **[Architecture](ARCHITECTURE.md)** — system design and data flow
- **[Cloud Setup](SETUP_CLOUD.md)** — Supabase + optional R2
- **[Contributing](CONTRIBUTING.md)** — code standards and PR flow
- **[Protocol](protocol.md)** — Oura BLE specification

## License

MIT — see [legal.md](legal.md) and [LICENSE](https://github.com/FasterApiWeb/laughing-chainsaw/blob/main/LICENSE).
