# librering-core

Shared Oura Ring BLE protocol logic in Rust.

## Purpose

Single source of truth for packet parsing and protocol constants, shared by:

- iOS (UniFFI → Swift)
- Android (UniFFI → Kotlin)
- Python tools (PyO3, future)

Today the Python (`tools/oura_protocol.py`) and Swift (`OuraProtocol.swift`) copies exist; migrate callers here over time.

## Build & test

```bash
cargo test
```

## Layout

```
src/
  error.rs     # ProtocolError
  packet.rs    # ParsedPacket
  protocol.rs  # UUIDs, command bytes, frame builder
```

## UniFFI (Phase 5 stub)

Enable the `uniffi` feature to generate mobile bindings:

```bash
cargo build --features uniffi
```

Full binding pipeline documented in [docs/CLIENTS.md](../../docs/CLIENTS.md).

## Sync with Python

When changing protocol constants, update:

1. `core/librering-core/src/protocol.rs`
2. `tools/oura_protocol.py`
3. `PROTOCOL.md`
