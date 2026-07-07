# LibreRing

**Your body. Your data. No subscription.**

LibreRing bypasses the Oura Ring subscription ($6/month) by connecting directly to your ring over Bluetooth, reading all sensor data locally, and syncing it to Apple Health. No cloud. No account. No paywall between you and the hardware you paid $300+ for.

Inspired by [LibrePods](https://github.com/nicklama/librepods) — if they can unlock AirPods on Android, we can unlock Oura on your terms.

## What it does

- Connects to Oura Ring 3/4/5 via BLE without the Oura app
- Reads HR, HRV, SpO2, temperature, sleep stages, steps, accelerometer
- Computes sleep score, readiness score, and HRV analysis with **open algorithms**
- Writes everything to **Apple Health** automatically
- Stores data locally in SQLite — export anytime as JSON/CSV
- Zero network permissions — your data never leaves your device

## How it works

The Oura Ring stores all sensor data on-device and streams it over Bluetooth Low Energy. The Oura app decodes this data, computes scores using PyTorch models, and uploads everything to Oura's cloud — gating access behind a subscription.

LibreRing speaks the same BLE protocol directly. Factory reset your ring, pair with LibreRing, and your data flows to Apple Health instead of Oura's servers.

## Project structure

```
ios/LibreRing/       # iOS app (Swift/SwiftUI, CoreBluetooth, HealthKit)
tools/               # Python reverse-engineering toolkit
  scan_oura.py       # BLE GATT discovery
  probe_oura.py      # Auth + firmware probe
  listen_oura.py     # Live notification capture
  pair_oura.py       # Cloud-free pairing
  read_battery.py    # Authenticated battery read
  ring_ctl.py        # Factory reset
  oura_protocol.py   # Protocol implementation
  oura_ble.py        # BLE session helpers
PROTOCOL.md          # Oura BLE protocol specification
```

## iOS app

### Prerequisites
- iPhone with iOS 17+
- Xcode 16+
- Oura Ring (Gen 3, 4, or 5) — factory reset

### Build & run

```bash
cd ios/LibreRing
brew install xcodegen    # one-time
xcodegen generate        # creates .xcodeproj from project.yml
open LibreRing.xcodeproj
```

Build and run on your iPhone (BLE requires a physical device, not simulator).

### Setup flow
1. Factory reset your ring (Oura app → Settings → Reset, or use `tools/ring_ctl.py`)
2. Open LibreRing → Scan → tap your ring to pair
3. Grant Bluetooth and HealthKit permissions
4. Ring syncs automatically — data appears in Apple Health

### What syncs to Apple Health
| Metric | HealthKit Type |
|--------|---------------|
| Heart rate | `heartRate` |
| HRV | `heartRateVariabilitySDNN` |
| SpO2 | `oxygenSaturation` |
| Temperature | `bodyTemperature` |
| Sleep stages | `sleepAnalysis` (awake/core/deep/REM) |
| Steps | `stepCount` |

## RE toolkit (Python)

The `tools/` directory contains the reverse-engineering scripts used to map the Oura BLE protocol.

```bash
cd tools
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python scan_oura.py --read-values       # GATT discovery
python probe_oura.py --key-file key.hex # auth + firmware
python listen_oura.py --key-file key.hex --duration 60
```

See [PROTOCOL.md](PROTOCOL.md) for the full BLE protocol specification.

## Protocol references

- [ringverse/protocol](https://github.com/ringverse/protocol) — community Oura BLE protocol docs (80+ event types)
- [open_oura](https://github.com/Th0rgal/open_oura) — Rust CLI for Oura rings (MIT)

## Roadmap

- [x] BLE protocol reverse engineering (auth, battery, firmware, notifications)
- [x] iOS app with CoreBluetooth + HealthKit
- [ ] Background sync (BGTaskScheduler)
- [ ] Android app with Health Connect
- [ ] Shared Rust core (UniFFI bindings for iOS + Android)
- [ ] PyPI package for protocol library

## Legal

Clean-room reverse engineering under DMCA §1201(f) for interoperability. LibreRing does not distribute proprietary code, modify firmware, or bypass DRM. It reads publicly-broadcast BLE signals from hardware the user owns.

## Personal data (gitignored)

Never commit these — they contain your ring auth key, device UUIDs, or health payloads:

| Path | Contents |
|------|----------|
| `key.hex` | 16-byte BLE auth key |
| `tools/services.json` | GATT dump + CoreBluetooth UUID |
| `tools/captures/` | probe/listen logs, `.pklg`, API captures |

Use `key.hex.example` as a template. Generate a real key with `tools/pair_oura.py`.

## License

MIT
