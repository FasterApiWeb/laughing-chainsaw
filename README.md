# LibreRing (laughing-chainsaw)

Reverse-engineer the Oura Ring BLE protocol for local, subscription-free access to your biometric data.

## Quick start

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 1. Map GATT surface
python scan_oura.py --read-values

# 2. Probe protocol (nonce, firmware; add key after pairing)
python probe_oura.py
python probe_oura.py --key-file key.hex

# 3. Listen for live notifications
python listen_oura.py --duration 120

# 4. Pair a factory-reset ring (cloud-free)
python pair_oura.py

# 5. Read battery (requires key.hex)
python read_battery.py --key-file key.hex
```

## Tools

| Script | Purpose |
|--------|---------|
| `scan_oura.py` | Discover ring, dump GATT → `services.json` |
| `listen_oura.py` | Subscribe to all notify characteristics |
| `probe_oura.py` | Auth nonce, firmware, battery probe + JSONL log |
| `pair_oura.py` | Install new auth key on factory-reset ring |
| `read_battery.py` | Authenticated battery read |
| `ring_ctl.py` | Factory reset (requires key) |
| `parse_pklg.py` | PacketLogger `.pklg` → ATT timeline |
| `capture_api.py` | mitmproxy addon for `cloud.ouraring.com` |
| `correlate.py` | Match API + BLE captures by timestamp |
| `pairing_analysis.py` | macOS BLE pairing vs app-auth notes |

Shared modules: `oura_protocol.py`, `oura_ble.py`, `oura_parsers.py`.

See [PROTOCOL.md](PROTOCOL.md) for GATT map and auth flow.

## Personal data (gitignored)

- `services.json`, `key.hex`, `captures/` — never commit these.
