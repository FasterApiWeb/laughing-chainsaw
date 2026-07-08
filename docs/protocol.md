# BLE Protocol

The full Oura Ring BLE protocol specification lives in the repository root:

**[PROTOCOL.md on GitHub](https://github.com/FasterApiWeb/laughing-chainsaw/blob/main/PROTOCOL.md)**

## Quick reference

| Item | Value |
|------|-------|
| Service UUID | `98ed0001-a541-11e4-b6a0-0002a5d5c51b` |
| Command char | `98ed0002-a541-11e4-b6a0-0002a5d5c51b` |
| Data char | `98ed0003-a541-11e4-b6a0-0002a5d5c51b` |
| Auth | 16-byte key after factory reset + pairing |

## Implementations

| Location | Language |
|----------|----------|
| `tools/oura_protocol.py` | Python (RE toolkit) |
| `apps/ios/.../OuraProtocol.swift` | Swift (iOS app) |
| `core/librering-core/` | Rust (shared core) |

## RE toolkit

```bash
cd tools
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python scan_oura.py --read-values
python probe_oura.py --key-file ../key.hex.example
```

Never commit a real `key.hex` — use `key.hex.example` as a template.

## Community references

- [ringverse/protocol](https://github.com/ringverse/protocol)
- [open_oura](https://github.com/Th0rgal/open_oura)
