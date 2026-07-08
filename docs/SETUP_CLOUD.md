# Cloud setup walkthrough

Step-by-step guide to connect Supabase + Cloudflare Worker to the web app and iOS.

**Time:** ~30 minutes  
**Cost:** Free tier on both services

---

## Part 1 — Supabase (auth + database)

### Step 1: Create project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard)
2. **New project** → name it `librering`, set a strong DB password, pick a region close to you
3. Wait ~2 minutes for provisioning

### Step 2: Copy API keys

1. **Project Settings** → **API**
2. Save these somewhere local (password manager, not git):
   - **Project URL** → `https://xxxxx.supabase.co`
   - **anon public** key
   - **JWT Secret** (under JWT Settings) → needed for Worker

### Step 3: Run migrations

1. **SQL Editor** → **New query**
2. Paste entire contents of `backend/supabase/migrations/001_initial.sql` → **Run**
3. New query → paste `backend/supabase/migrations/002_sync_rpc_full.sql` → **Run**

Verify in **Table Editor**: you should see `profiles`, `devices`, `heart_rate`, etc.

### Step 4: Configure Authentication (important)

LibreRing uses **email + password** in the browser ([Supabase password auth](https://supabase.com/docs/guides/auth/passwords)). You only need two dashboard pages.

#### A) Email provider — allow instant signup (recommended for dev)

1. Dashboard → **Authentication** → **Sign In / Providers** (or **Providers**)
2. Click **Email**
3. Ensure **Enable Email provider** is ON
4. Turn **OFF** → **Confirm email**

Why? On hosted Supabase, [email confirmation is ON by default](https://supabase.com/docs/guides/auth/passwords). If it stays on, signup sends a confirmation email and you **cannot log in** until you click the link. Default SMTP also limits you to ~2 emails/hour.

With Confirm email off, [Supabase treats the email as verified immediately](https://supabase.com/docs/guides/auth/general-configuration) — perfect for local testing.

#### B) URL Configuration — where auth redirects go

1. Dashboard → **Authentication** → **URL Configuration**
2. Set **Site URL** to:
   ```
   http://localhost:3000
   ```
3. Under **Redirect URLs**, click **Add URL** and add:
   ```
   http://localhost:3000/**
   ```

Docs: [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls). Site URL is the default redirect when none is specified (email links, password reset). The wildcard entry allows local dev.

> **GitHub Pages later:** change Site URL to `https://fasterapiweb.github.io/laughing-chainsaw/` and add that URL + `/**` to Redirect URLs.

You do **not** need custom SMTP, OAuth providers, or MFA for basic testing.

### Step 5: Wire the web app

If you already filled `backend/supabase/.env`:

```bash
pnpm wire:env    # copies keys → apps/web/.env.local
```

Or manually:

```bash
cp apps/web/.env.example apps/web/.env.local
# paste SUPABASE_URL and anon key
```

```bash
pnpm install
pnpm test:supabase   # should pass
pnpm dev:web
```

### Step 6: Test web auth + sync

1. Open `http://localhost:3000`
2. **Sign up** with a test email/password
3. **Upload** a sample export or import JSON on `/upload`
4. **Settings** → **Sync Now**
5. In Supabase **Table Editor** → `heart_rate` → confirm rows appear
6. Check `devices` table for your registered web client

---

## Part 2 — Cloudflare Worker + R2 (blob storage)

> Optional for v1. Web sync works without this. Needed for large export backups to R2.

### Step 1: Install Wrangler

```bash
npm install -g wrangler
wrangler login
```

### Step 2: Create R2 bucket

```bash
wrangler r2 bucket create librering-exports
```

### Step 3: Set Worker secrets

```bash
cd backend/worker
wrangler secret put SUPABASE_JWT_SECRET
# paste JWT secret from Supabase dashboard
```

Edit `backend/worker/wrangler.toml` — set your Supabase URL in `[vars]`:

```toml
[vars]
SUPABASE_URL = "https://YOUR_REF.supabase.co"
```

### Step 4: Deploy Worker

```bash
pnpm install
pnpm --filter @librering/worker deploy
```

Note the deployed URL (e.g. `https://librering-api.your-subdomain.workers.dev`).

### Step 5: Wire Worker URL to web

Add to `apps/web/.env.local`:

```env
NEXT_PUBLIC_WORKER_URL=https://librering-api.your-subdomain.workers.dev
```

Restart `pnpm dev:web`.

### Step 6: Test Worker health

```bash
curl https://YOUR_WORKER_URL/health
# → {"status":"ok"}
```

---

## Part 3 — iOS app

### Step 1: Configure Supabase keys (optional)

```bash
cp apps/ios/LibreRing/Secrets.xcconfig.example \
   apps/ios/LibreRing/Secrets.xcconfig.local
```

Edit `Secrets.xcconfig.local` with your URL and anon key.

### Step 2: Build on device

```bash
cd apps/ios/LibreRing
xcodegen generate
open LibreRing.xcodeproj
```

1. Select your **iPhone** as run target (BLE needs hardware)
2. **Product → Run**
3. Settings → Cloud Sync shows **Off** until keys are set; BLE works without cloud

### Step 3: Verify no regressions

- [ ] Scan finds ring
- [ ] Pair + auth works
- [ ] Dashboard shows data after sync
- [ ] HealthKit write succeeds
- [ ] Export JSON works

---

## Part 4 — GitHub Pages (production web)

### Step 1: Set repository variables

GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **Variables**:

| Variable | Value |
|----------|-------|
| `NEXT_PUBLIC_SUPABASE_URL` | your Supabase URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | anon key |

### Step 2: Push to main

The workflow `.github/workflows/deploy-desktop.yml` builds and deploys `apps/web/out`.

### Step 3: Update Supabase Site URL

Add your GitHub Pages URL to Supabase **Authentication → URL Configuration**:

```
https://fasterapiweb.github.io/laughing-chainsaw/
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Signup returns error | Check anon key; disable email confirm for testing |
| Sync Now fails "not authenticated" | Sign out and back in; check `.env.local` |
| Sync fails "FOREACH expression must not be null" | Run `004_fix_null_foreach.sql` in SQL Editor |
| Sync fails "row-level security" on devices | Run `003_devices_rls_fix.sql` in SQL Editor |
| Sync fails "device not found" | DevTools → Application → Local Storage → delete `librering_device_id`, sync again |
| RLS blocks insert | Ensure you're logged in; run migration 003 |
| iOS build fails on Secrets | Ensure `apps/ios/LibreRing/Secrets.xcconfig` exists (committed empty default) |
| Worker 401 | JWT secret mismatch; token expired — re-login |

---

## Security checklist before push

```bash
# These must NOT appear in git status:
git status | grep -E 'key\.hex|\.env\.local|Secrets\.xcconfig\.local|captures|\.jsonl'
# (no output = good)

# Verify gitignore:
git check-ignore -v key.hex apps/web/.env.local
```

Never commit: `key.hex`, `.env.local`, `Secrets.xcconfig.local`, `captures/`, `*.jsonl`, `services.json`.
