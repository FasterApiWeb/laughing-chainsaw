# Legal & Interoperability

!!! warning "Not legal advice"
    This document describes the project's engineering and interoperability posture. It is not legal advice. Consult qualified counsel for your jurisdiction.

## Summary

LibreRing is **clean-room reverse engineering for interoperability** under U.S. DMCA §1201(f) and similar laws in other jurisdictions where applicable.

## What LibreRing does

- Connects to **Oura Ring hardware you own** over standard Bluetooth Low Energy
- Reads GATT characteristics the ring advertises when paired
- Stores and displays decoded health metrics locally
- Optionally syncs to **your own** cloud account (Supabase)

## What LibreRing does not do

- Modify Oura ring firmware
- Distribute Oura proprietary binaries, models, or server code
- Bypass DRM on encrypted third-party media
- Impersonate the official Oura app or servers
- Enable use of stolen or shared rings

## Trademarks

**Oura**, **Oura Ring**, and related marks are trademarks of Oura Health Oy. LibreRing is an **independent, open-source project** and is not affiliated with, endorsed by, or sponsored by Oura Health Oy.

## License

Source code is released under the **[MIT License](https://github.com/FasterApiWeb/laughing-chainsaw/blob/main/LICENSE)**.

Third-party references:

- [ringverse/protocol](https://github.com/ringverse/protocol) — community BLE docs
- [open_oura](https://github.com/Th0rgal/open_oura) — MIT Rust CLI

## Health data disclaimer

LibreRing is **not a medical device**. Metrics and scores are for wellness tracking only. Do not use for diagnosis or treatment decisions.

## Contributing legally

- Do not commit Oura app decompiled code, APKs, or proprietary ML weights
- Do not commit personal `key.hex`, captures, or health logs — see `.gitignore`
- Document protocol findings in `PROTOCOL.md` from observable BLE behavior

## Reporting concerns

Security issues: see [security.md](security.md).

Legal questions: open a [GitHub Discussion](https://github.com/FasterApiWeb/laughing-chainsaw/discussions) or issue tagged `legal`.
