# Deploy web app to GitHub Pages

Production URL: **https://fasterapiweb.github.io/laughing-chainsaw/**

## One-time GitHub setup

1. Repo → **Settings** → **Pages**
   - Source: **GitHub Actions** (not “Deploy from branch”)

2. Repo → **Settings** → **Secrets and variables** → **Actions** → **Variables** tab → **New repository variable**:

   | Name | Value |
   |------|-------|
   | `NEXT_PUBLIC_SUPABASE_URL` | `https://YOUR_REF.supabase.co` |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | anon key from Supabase dashboard |

   Use the same values as `backend/supabase/.env` (never commit those files).

3. **Supabase** → **Authentication** → **URL Configuration**:
   - **Site URL:** `https://fasterapiweb.github.io/laughing-chainsaw/`
   - **Redirect URLs:** add `https://fasterapiweb.github.io/laughing-chainsaw/**`

4. For local dev, keep separate URLs:
   - Site URL can stay `http://localhost:3000` while developing locally
   - Production users hit GitHub Pages — add both redirect URLs if you use email confirm

## Deploy

Push to `main` — workflow `.github/workflows/deploy-desktop.yml` runs when `apps/web/`, `packages/sdk-ts/`, or `pnpm-lock.yaml` change.

Manual trigger: **Actions** → **Deploy Web to GitHub Pages** → **Run workflow**.

## Verify

1. Actions tab shows green build
2. Open https://fasterapiweb.github.io/laughing-chainsaw/
3. Sign up / log in
4. Import data → **Settings** → **Sync Now**
5. Check Supabase Table Editor for new rows

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Build fails on pnpm | Ensure `pnpm-lock.yaml` is committed |
| Auth works locally but not on Pages | Add Pages URL to Supabase redirect URLs |
| Cloud sync disabled on Pages | Set GitHub Actions variables (step 2) |
| 404 on routes | `basePath` is `/laughing-chainsaw` — use full path URLs |

See also [SETUP_CLOUD.md](./SETUP_CLOUD.md) for Supabase + sync setup.
