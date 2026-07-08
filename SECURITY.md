# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| `main` branch | ✅ Active development |
| Tagged releases (`v*.*.*`) | ✅ Latest release only |

## Reporting a vulnerability

**Please do not open public issues for security vulnerabilities.**

1. Go to [GitHub Security Advisories](https://github.com/FasterApiWeb/laughing-chainsaw/security/advisories/new) and open a **private** report, **or**
2. Open a GitHub issue with minimal detail and ask for a private channel

Include:

- Description of the issue and impact
- Steps to reproduce
- Affected component (web, iOS, worker, Supabase migrations, tools)
- Suggested fix (if any)

We aim to acknowledge reports within **7 days**.

## Scope

In scope:

- LibreRing source code in this repository
- Documented deployment configurations (GitHub Actions, Supabase RLS)

Out of scope:

- Oura Health Oy infrastructure or official app
- User misconfiguration of Supabase keys (use RLS; never expose service role keys in clients)
- Physical theft of a user's `key.hex` from their device

## Safe defaults

- Supabase tables use Row Level Security (`auth.uid() = user_id`)
- BLE auth keys and captures are gitignored
- Worker validates JWT before R2 access
- Web app uses anon key only — never service role in frontend

## Security hygiene for contributors

- Never commit `.env`, `key.hex`, or capture logs
- Run `git check-ignore -v key.hex` before pushing
- Review Supabase migration RLS policies in PRs
