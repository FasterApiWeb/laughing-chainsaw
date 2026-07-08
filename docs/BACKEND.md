# Backend setup

LibreRing uses a **hybrid backend**:

- **Supabase** — Auth, Postgres, Row Level Security, sync RPCs
- **Cloudflare Worker + R2** — presigned upload/download for large files

> **Step-by-step:** [SETUP_CLOUD.md](./SETUP_CLOUD.md)

## Prerequisites

- [Supabase](https://supabase.com) free tier project
- [Cloudflare](https://cloudflare.com) account with R2 enabled
- Node 20+, pnpm 9+

## 1. Supabase

### Create project

1. New project at supabase.com
2. Copy **Project URL** and **anon key** from Settings → API
3. Copy **JWT secret** (Worker needs this to verify tokens)

### Apply migrations

```bash
# Option A: Supabase CLI
cd backend/supabase
supabase link --project-ref YOUR_REF
supabase db push

# Option B: SQL editor — paste in order:
#   migrations/001_initial.sql
#   migrations/002_sync_rpc_full.sql
```

### Environment

Copy `backend/supabase/.env.example` → `.env` (local only, gitignored).

### Tables

| Table | Purpose |
|-------|---------|
| `profiles` | User profile (auto-created on signup) |
| `devices` | Registered rings / clients |
| `sync_cursors` | Last sync cursor per user + device |
| `heart_rate`, `spo2`, … | Time-series metrics |
| `storage_objects` | R2 object metadata |

### RPCs

| Function | Description |
|----------|-------------|
| `push_sync_batch(device_id, cursor, batches)` | Upsert metric batches |
| `pull_sync_delta(device_id, since_cursor, tables?)` | Pull remote changes |

All tables use RLS: `auth.uid() = user_id`.

## 2. Cloudflare Worker (R2)

### Create R2 bucket

```bash
wrangler r2 bucket create librering-exports
```

### Configure secrets

```bash
cd backend/worker
wrangler secret put SUPABASE_JWT_SECRET
# Set SUPABASE_URL in wrangler.toml [vars] or dashboard
```

### Deploy

```bash
pnpm install
pnpm dev:worker    # local
pnpm --filter @librering/worker deploy
```

### Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/health` | No | Liveness |
| POST | `/v1/storage/upload-url` | Bearer JWT | Presigned upload |
| POST | `/v1/storage/download-url` | Bearer JWT | Presigned download |

Object keys are scoped: `{user_id}/{timestamp}-{filename}`.

## 3. Wire clients

### Web

```bash
cp apps/web/.env.example apps/web/.env.local
# Set NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, NEXT_PUBLIC_WORKER_URL
pnpm install
pnpm dev:web
```

### iOS

Add to `Info.plist` (or xcconfig):

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_REF.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>your-anon-key</string>
```

### Android

```bash
cp apps/android/gradle.properties.example apps/android/gradle.properties
```

## Free tier notes

| Service | Limit | Mitigation |
|---------|-------|------------|
| Supabase | 500 MB DB, pauses after 1 week idle | Optional Worker cron ping; keep project active |
| Cloudflare R2 | 10 GB storage, free egress to Workers | Use for blobs only |
| Cloudflare Workers | 100k req/day | Presigned URLs minimize Worker hits |

## Security checklist

- [ ] RLS enabled on all public tables
- [ ] Never commit `.env`, `key.hex`, or service role keys
- [ ] Worker validates JWT + user owns object key prefix
- [ ] Use anon key in clients; service role only in CI/admin scripts
