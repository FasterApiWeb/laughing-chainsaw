# Client development guide

How each LibreRing client fits together and where to add code.

## Shared concepts

| Concept | Web | iOS | Android |
|---------|-----|-----|---------|
| Local DB | Dexie (`apps/web/src/lib/db.ts`) | SQLite (`LocalStore.swift`) | Room (`LibreRingDatabase.kt`) |
| Auth port | `@librering/sdk` AuthService | Supabase Swift (future) / REST | Supabase Kotlin (future) |
| Sync port | `SyncService` + `sync.ts` | `SyncRepository` protocol | `SyncRepository` interface |
| Blob port | `StorageService` → Worker | Worker REST | Worker REST |
| BLE protocol | N/A (import only) | `OuraProtocol.swift` → `librering-core` | `librering-core` via UniFFI |

## Web (`apps/web`)

**Stack:** Next.js 16 static export, Dexie, `@librering/sdk`

```bash
pnpm install
cp apps/web/.env.example apps/web/.env.local   # optional cloud
pnpm dev:web
```

| Task | File |
|------|------|
| Add chart | `src/app/dashboard/` |
| Import parser | `src/lib/ingest*.ts` |
| Cloud sync | `src/lib/sync.ts` |
| Auth | `src/lib/auth.ts` (wraps SDK) |

Deploys to GitHub Pages at `/laughing-chainsaw` base path.

## iOS (`apps/ios/LibreRing`)

**Stack:** Swift 6, SwiftUI, CoreBluetooth, HealthKit, SQLite

```bash
cd apps/ios/LibreRing
brew install xcodegen
xcodegen generate
open LibreRing.xcodeproj
```

| Task | Location |
|------|----------|
| BLE session | `BLE/BLEManager.swift` |
| Protocol | `BLE/OuraProtocol.swift` → migrate to Rust |
| Local storage | `Storage/LocalStore.swift` |
| Cloud sync | `Sync/SyncEngine.swift`, `Sync/SupabaseSyncRepository.swift` |
| HealthKit | `Health/HealthKitManager.swift` |

Requires physical iPhone (BLE).

## Android (`apps/android`)

**Stack:** Kotlin, Jetpack Compose, Room (scaffold)

See [apps/android/README.md](../apps/android/README.md).

## TypeScript SDK (`packages/sdk-ts`)

```bash
pnpm build:sdk
```

Public API:

```typescript
import { createLibreRingClient } from "@librering/sdk";

const client = createLibreRingClient({
  supabaseUrl: "...",
  supabaseAnonKey: "...",
  workerUrl: "https://api.librering.dev",
});

await client.auth.signIn(email, password);
await client.sync.push({ deviceId, cursor, batches });
```

**SOLID mapping:**

- `AuthService` — interface (Dependency Inversion)
- `SupabaseAuthService` — Single Responsibility
- `LibreRingClient` — Facade for app code

## Rust core (`core/librering-core`)

Shared BLE packet parsing and constants. Ported from `tools/oura_protocol.py`.

```bash
cd core/librering-core
cargo test
```

UniFFI bindings (Phase 5 stub) will generate Swift/Kotlin bindings for mobile.

## Python tools (`tools/`)

Reverse-engineering CLIs — not part of cloud sync. Use for protocol research and hardware testing.

## Adding a new metric end-to-end

1. Add column/table in `backend/supabase/migrations/`
2. Extend `push_sync_batch` / `pull_sync_delta`
3. Add Dexie table + `sync.ts` mapping
4. Add SQLite/Room schema on mobile
5. Update `packages/api-spec/openapi.yaml` schemas

## Testing sync locally

1. Apply Supabase migrations
2. Set web `.env.local`
3. Sign up in web app
4. Import sample data → Settings → Sync Now
5. Verify rows in Supabase Table Editor
