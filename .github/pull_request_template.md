## Summary

<!-- What changed and why? Link issues with "Fixes #123" -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Backend / migration
- [ ] iOS / Android
- [ ] Refactor

## Checklist

- [ ] No secrets in diff (`key.hex`, `.env`, captures, `services.json`)
- [ ] `pnpm lint:web && pnpm build:web` pass (if web touched)
- [ ] `pnpm typecheck:worker` pass (if worker touched)
- [ ] `cargo test -p librering-core` pass (if Rust touched)
- [ ] Supabase migration added if schema changed (numbered file in `backend/supabase/migrations/`)
- [ ] Docs updated (`docs/` or `mkdocs.yml` if user-facing)

## Test plan

<!-- How did you verify? Device, browser, SQL editor, etc. -->
