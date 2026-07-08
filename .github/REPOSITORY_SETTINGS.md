# GitHub Repository Settings

Apply these in **Settings → General** for [FasterApiWeb/laughing-chainsaw](https://github.com/FasterApiWeb/laughing-chainsaw/settings).

## About (sidebar)

| Field | Value |
|-------|-------|
| **Description** | Open-source Oura Ring client — direct BLE, HealthKit, optional Supabase sync. No subscription. |
| **Website** | https://fasterapiweb.github.io/laughing-chainsaw/docs/ |
| **Topics** | `oura-ring`, `bluetooth-low-energy`, `ble`, `healthkit`, `health-data`, `open-source`, `ios`, `swift`, `nextjs`, `supabase`, `reverse-engineering`, `sleep-tracking`, `heart-rate-variability`, `monorepo`, `cloudflare`, `rust` |

## Features to enable

- [x] Issues
- [x] Discussions (recommended for Q&A)
- [ ] Wikis (disabled — use MkDocs instead)
- [x] Projects (optional)

## Pages

- **Source:** GitHub Actions (`deploy-pages.yml`)
- **Dashboard:** https://fasterapiweb.github.io/laughing-chainsaw/
- **Docs:** https://fasterapiweb.github.io/laughing-chainsaw/docs/

## Actions variables

Settings → Secrets and variables → Actions → **Variables**:

| Name | Purpose |
|------|---------|
| `NEXT_PUBLIC_SUPABASE_URL` | Web build + Pages deploy |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Web build + Pages deploy |

## Branch protection (recommended)

For `main`:

- Require PR before merge
- Require status checks: `Web (lint + build)`, `Docs (MkDocs build)`, `No secrets in tree`
- Require linear history (optional)

## Releases

Push a semver tag to create a release with web export zip:

```bash
git tag v0.2.0
git push origin v0.2.0
```

## Custom properties (organization)

If your org uses GitHub custom properties:

| Property | Value |
|----------|-------|
| `license` | MIT |
| `language` | TypeScript, Swift, Python, Rust |
| `documentation` | mkdocs-material |
| `deployment` | github-pages |

See [docs/OPEN_SOURCE.md](../docs/OPEN_SOURCE.md) for the full checklist.
