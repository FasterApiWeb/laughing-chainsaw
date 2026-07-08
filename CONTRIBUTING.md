# Contributing to LibreRing

Thanks for your interest in LibreRing! Please read the full guide before opening a PR.

**Full documentation:** [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) · [docs site](https://fasterapiweb.github.io/laughing-chainsaw/docs/CONTRIBUTING/)

## Quick start

```bash
git clone https://github.com/FasterApiWeb/laughing-chainsaw.git
cd laughing-chainsaw
pnpm install
pnpm dev:web
```

## Before you PR

- [ ] No secrets (`key.hex`, `.env`, captures) in the diff
- [ ] `pnpm lint:web && pnpm build:web` pass (for web changes)
- [ ] Migrations numbered sequentially in `backend/supabase/migrations/`
- [ ] Docs updated if behavior or setup changed

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## Questions?

Open a [GitHub Discussion](https://github.com/FasterApiWeb/laughing-chainsaw/discussions) or issue with the `question` label.
