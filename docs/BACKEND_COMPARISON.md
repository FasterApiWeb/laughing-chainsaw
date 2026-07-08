# Backend comparison matrix

Why LibreRing uses **Supabase + Cloudflare R2** (hybrid) instead of a single vendor.

## Options considered

| | **Hybrid (chosen)** | **Option A: Cloudflare-only** | **Supabase-only** |
|---|---------------------|----------------------------------|-------------------|
| Auth | Supabase Auth | Cloudflare Access / custom JWT | Supabase Auth |
| Structured DB | Supabase Postgres + RLS | D1 (SQLite) or Turso | Supabase Postgres |
| Blob storage | Cloudflare R2 | Cloudflare R2 | Supabase Storage |
| API layer | PostgREST + Worker | Workers only | PostgREST |
| Mobile SDKs | supabase-swift, supabase-kt, JS | Custom REST | Official SDKs |
| Free tier DB | 500 MB Postgres | D1 5 GB (beta limits) | 500 MB |
| Free tier blobs | R2 10 GB | R2 10 GB | 1 GB |

## Why not Supabase-only?

Supabase **is** in our stack — for auth and Postgres. We deliberately **do not** use Supabase Storage for blobs because:

1. **Storage quota** — 1 GB on free tier fills quickly with Oura ZIP exports
2. **Egress cost** — R2 has zero egress to Workers; good for large file delivery
3. **Separation of concerns** — metrics in SQL, files in object storage (standard pattern)
4. **Idle pause risk** — concentrating everything on Supabase increases blast radius if project pauses

## Why not pure Option A (Cloudflare-only)?

Cloudflare-only is viable but we chose hybrid for:

1. **Auth DX** — Supabase Auth + RLS is faster to ship than custom JWT + D1 policies
2. **Postgres** — richer queries, migrations, and tooling vs D1 SQLite subset
3. **Official mobile SDKs** — supabase-swift / supabase-kt reduce client boilerplate
4. **RLS** — row-level security is first-class in Postgres; D1 RLS is newer/limited

## Why Supabase appears in the matrix at all

| Need | Supabase strength | R2 strength |
|------|-------------------|-------------|
| Sign up / login | ✅ Built-in | ❌ Roll your own |
| Sync heart_rate rows | ✅ Postgres + RPC | ❌ Wrong tool |
| Store 50 MB Oura export | ⚠️ Tight quota | ✅ Cheap objects |
| Presigned browser upload | ⚠️ Possible | ✅ Native pattern |

**Conclusion:** Use each tool for what it does best. Clients talk to Supabase for auth/sync and to the Worker for blobs — one SDK facade (`@librering/sdk`) hides the split.

## When to reconsider

Switch toward **Option A** if:

- Supabase free tier becomes a blocker at scale
- You want zero external DB vendor
- D1 + R2 + Workers meets all query needs

Switch toward **Supabase-only** if:

- Blob volume stays under 1 GB
- You want one dashboard/bill
- Worker ops cost exceeds benefit

## Decision record

- **Date:** 2026-07
- **Decision:** Hybrid Supabase (auth + Postgres) + Cloudflare R2 (blobs) + Worker (presigned URLs)
- **Status:** Implemented in phases 1–5 scaffold
