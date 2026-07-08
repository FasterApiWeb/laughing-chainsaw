# Android app (Phase 4 scaffold)

Kotlin + Jetpack Compose scaffold for LibreRing on Android.

## Status

- [x] Project structure (`app/`, Room database stub)
- [x] Sync repository interface (mirrors iOS `SyncRepository`)
- [ ] BLE via Rust `librering-core` (UniFFI)
- [ ] Health Connect integration
- [ ] Supabase Kotlin SDK wiring

## Build

```bash
cd apps/android
cp gradle.properties.example gradle.properties   # optional cloud keys
./gradlew :app:assembleDebug
```

Open in Android Studio Hedgehog+.

## Architecture

Follows the same offline-first pattern as iOS:

1. **Room** — local source of truth
2. **Supabase RPC** — structured sync (`push_sync_batch`, `pull_sync_delta`)
3. **Cloudflare Worker** — R2 blob storage for exports

See [docs/CLIENTS.md](../../docs/CLIENTS.md) for cross-platform conventions.
