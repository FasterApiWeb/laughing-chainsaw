# Open Source Readiness

Checklist for maintaining LibreRing as a healthy open-source project.

## Repository metadata (GitHub UI)

Set these under **Settings → General** for [FasterApiWeb/laughing-chainsaw](https://github.com/FasterApiWeb/laughing-chainsaw):

| Field | Recommended value |
|-------|-------------------|
| **Description** | Open-source Oura Ring client — BLE, HealthKit, optional Supabase sync. No subscription. |
| **Website** | `https://fasterapiweb.github.io/laughing-chainsaw/docs/` |
| **Topics** | `oura-ring`, `bluetooth-low-energy`, `healthkit`, `open-source`, `ios`, `swift`, `nextjs`, `supabase`, `reverse-engineering`, `sleep-tracking`, `heart-rate`, `health-data`, `monorepo` |

### Custom properties (optional)

If your org uses GitHub custom properties:

| Property | Value |
|----------|-------|
| `license` | MIT |
| `status` | active |
| `docs-site` | mkdocs-material |

## Files & policies

| File | Purpose | Status |
|------|---------|--------|
| `LICENSE` | MIT | ✅ |
| `CODE_OF_CONDUCT.md` | Community standards | ✅ |
| `SECURITY.md` | Vulnerability reporting | ✅ |
| `CONTRIBUTING.md` | Contributor guide | ✅ |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR checklist | ✅ |
| `.github/ISSUE_TEMPLATE/` | Bug & feature forms | ✅ |

## CI / CD (GitHub Actions)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PR + push to `main` | Lint, build, typecheck, Rust tests |
| `deploy-pages.yml` | push to `main` (web/docs paths) | Web dashboard + MkDocs site |
| `release.yml` | tag `v*.*.*` | GitHub Release with notes |

## Deployments

| Target | URL | Workflow |
|--------|-----|----------|
| Web dashboard | https://fasterapiweb.github.io/laughing-chainsaw/ | `deploy-pages.yml` |
| Documentation | https://fasterapiweb.github.io/laughing-chainsaw/docs/ | `deploy-pages.yml` |

Required GitHub **Actions variables** (Settings → Secrets and variables → Actions → Variables):

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

## Packages & releases

| Artifact | Registry | Status |
|----------|----------|--------|
| `@librering/sdk` | npm (GitHub Packages) | Private monorepo — not published yet |
| `@librering/web` | — | Deployed as static export, not npm |
| iOS app | App Store / sideload | Build from Xcode locally |
| Python tools | PyPI | Planned — not published yet |
| `librering-core` | crates.io | Planned — not published yet |

Releases are created when you push a semver tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

## Secrets hygiene

Never commit:

- `key.hex`, `services.json`, `tools/captures/`
- `.env`, `.env.local`, `Secrets.xcconfig.local`
- Supabase service role keys

Run before every PR:

```bash
git check-ignore -v key.hex apps/web/.env.local
git status | grep -E 'key\.hex|\.env\.local|captures'
```

## Legal review summary

- ✅ MIT license with copyright holder
- ✅ No proprietary Oura code in tree
- ✅ Interoperability statement in docs/legal.md
- ✅ Trademark disclaimer (Oura Health Oy)
- ✅ Health data disclaimer (not a medical device)
- ✅ `.gitignore` blocks sensitive RE artifacts

## Documentation

Built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/):

```bash
pip install -r docs/requirements.txt
mkdocs serve    # http://127.0.0.1:8000
mkdocs build    # output in site/
```
