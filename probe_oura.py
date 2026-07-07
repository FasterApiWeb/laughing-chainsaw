#!/usr/bin/env python3
"""Probe Oura Ring: nonce, optional auth, firmware/battery — logs all GATT traffic."""

from __future__ import annotations

import asyncio
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import click
from bleak import BleakClient
from bleak.backends.device import BLEDevice
from bleak.exc import BleakError
from rich.console import Console

from oura_protocol import (
    CMD_AUTH_NONCE,
    CMD_BATTERY,
    CMD_FIRMWARE,
    authenticate_request,
    describe_packet,
    extract_auth_nonce,
    parse_packet,
)
from scan_oura import discover_oura_devices, print_discovered

console = Console()

CMD_CHAR = "98ed0002-a541-11e4-b6a0-0002a5d5c51b"
DATA_CHAR = "98ed0003-a541-11e4-b6a0-0002a5d5c51b"


def log_event(
    events: list[dict[str, Any]],
    output: Any,
    *,
    direction: str,
    op: str,
    uuid: str,
    data: bytes | bytearray | None,
    extra: dict[str, Any] | None = None,
) -> None:
    entry: dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "direction": direction,
        "op": op,
        "uuid": uuid,
        "length": len(data) if data is not None else 0,
        "hex": data.hex() if data else None,
    }
    if data:
        entry["parsed"] = parse_packet(bytes(data))
    if extra:
        entry.update(extra)
    events.append(entry)
    hex_preview = entry["hex"] or ""
    if len(hex_preview) > 64:
        hex_preview = hex_preview[:64] + "…"
    desc = describe_packet(bytes(data)) if data else ""
    console.print(
        f"[cyan]{entry['timestamp']}[/cyan] "
        f"[bold]{direction:>3}[/bold] {op:<14} "
        f"len={entry['length']} [green]{hex_preview or '-'}[/green]"
        + (f" [dim]{desc}[/dim]" if desc else "")
    )
    if output:
        output.write(json.dumps(entry, ensure_ascii=False) + "\n")
        output.flush()


async def transact(
    client: BleakClient,
    notify_queue: asyncio.Queue[bytes],
    events: list[dict[str, Any]],
    output: Any,
    *,
    name: str,
    request: bytes,
    listen_seconds: float = 2.0,
) -> list[bytes]:
    while not notify_queue.empty():
        notify_queue.get_nowait()

    await client.write_gatt_char(CMD_CHAR, request, response=True)
    log_event(events, output, direction="TX", op=name, uuid=CMD_CHAR, data=request)

    responses: list[bytes] = []
    deadline = asyncio.get_event_loop().time() + listen_seconds
    while asyncio.get_event_loop().time() < deadline:
        remaining = deadline - asyncio.get_event_loop().time()
        if remaining <= 0:
            break
        try:
            data = await asyncio.wait_for(notify_queue.get(), timeout=remaining)
            responses.append(data)
        except asyncio.TimeoutError:
            break

    if not responses:
        try:
            value = await client.read_gatt_char(DATA_CHAR)
            if value and any(value):
                responses.append(bytes(value))
                log_event(events, output, direction="RX", op=f"{name}_read", uuid=DATA_CHAR, data=value)
        except BleakError:
            pass

    return responses


def load_key(path: Path | None) -> bytes | None:
    if path is None or not path.exists():
        return None
    key = bytes.fromhex(path.read_text(encoding="utf-8").strip())
    if len(key) != 16:
        raise ValueError(f"auth key must be 16 bytes, got {len(key)}")
    return key


async def probe_device(
    device: BLEDevice,
    *,
    connect_timeout: float,
    output: Any,
    auth_key: bytes | None,
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    notify_queue: asyncio.Queue[bytes] = asyncio.Queue()

    def on_notify(_handle: int, data: bytearray) -> None:
        payload = bytes(data)
        log_event(events, output, direction="RX", op="notify", uuid=DATA_CHAR, data=payload)
        notify_queue.put_nowait(payload)

    async with BleakClient(device, timeout=connect_timeout) as client:
        log_event(
            events,
            output,
            direction="--",
            op="connected",
            uuid="",
            data=None,
            extra={"mtu": client.mtu_size, "address": device.address},
        )

        await client.start_notify(DATA_CHAR, on_notify)

        # Unauthenticated reads (firmware works pre-auth on Ring 4/5)
        for name, req in (("firmware", CMD_FIRMWARE), ("battery_pre_auth", CMD_BATTERY)):
            await transact(client, notify_queue, events, output, name=name, request=req)

        # Auth nonce
        nonce_responses = await transact(
            client, notify_queue, events, output, name="auth_nonce", request=CMD_AUTH_NONCE
        )
        nonce: bytes | None = None
        for resp in nonce_responses:
            nonce = extract_auth_nonce(resp)
            if nonce:
                break

        if nonce:
            console.print(f"[bold]Auth nonce:[/bold] {nonce.hex()} ({len(nonce)} bytes)")
        else:
            console.print("[yellow]No auth nonce parsed from responses.[/yellow]")

        if auth_key and nonce:
            auth_req = authenticate_request(auth_key, nonce)
            auth_responses = await transact(
                client, notify_queue, events, output, name="authenticate", request=auth_req
            )
            authed = any(
                parse_packet(r).get("auth_state_name") == "success" for r in auth_responses
            )
            if authed:
                console.print("[bold green]Authentication succeeded.[/bold green]")
                await transact(
                    client, notify_queue, events, output, name="battery_post_auth", request=CMD_BATTERY
                )
            else:
                for resp in auth_responses:
                    parsed = parse_packet(resp)
                    state = parsed.get("auth_state_name", "unknown")
                    console.print(f"[red]Auth failed:[/red] {state}")
        elif auth_key:
            console.print("[yellow]Have key but no nonce — skipped authenticate.[/yellow]")
        else:
            console.print(
                "[dim]No --key-file: stopped after nonce. "
                "Provide key.hex from Oura app pairing to unlock battery/sensor data.[/dim]"
            )

        await client.stop_notify(DATA_CHAR)

    return events


@click.command()
@click.option("--timeout", "-t", default=15.0, show_default=True)
@click.option("--connect-timeout", default=30.0, show_default=True)
@click.option("--address", "-a", default=None)
@click.option(
    "--key-file",
    "-k",
    type=click.Path(path_type=Path),
    default=None,
    help="16-byte auth key as hex in a file (32 hex chars).",
)
@click.option(
    "--output",
    "-o",
    type=click.Path(path_type=Path),
    default=Path("captures/ble/probe.jsonl"),
    show_default=True,
)
def main(
    timeout: float,
    connect_timeout: float,
    address: str | None,
    key_file: Path | None,
    output: Path,
) -> None:
    """Probe Oura Ring protocol and log GATT traffic to JSONL."""

    async def _run() -> None:
        auth_key: bytes | None = None
        if key_file:
            try:
                auth_key = load_key(key_file)
            except ValueError as exc:
                console.print(f"[red]{exc}[/red]")
                sys.exit(1)

        console.print(f"[bold]Scanning ({timeout:.0f}s)…[/bold]")
        devices = await discover_oura_devices(timeout)
        print_discovered(devices)
        if not devices:
            sys.exit(1)

        if address:
            matches = [d for d, _ in devices if d.address == address]
            if not matches:
                console.print(f"[red]No device matches {address!r}[/red]")
                sys.exit(1)
            target = matches[0]
        else:
            target = devices[0][0]

        output.parent.mkdir(parents=True, exist_ok=True)
        console.print(f"[bold]Probing {target.name or target.address}…[/bold]")
        console.print(f"[dim]Logging → {output}[/dim]\n")

        with output.open("a", encoding="utf-8") as fh:
            try:
                events = await probe_device(
                    target,
                    connect_timeout=connect_timeout,
                    output=fh,
                    auth_key=auth_key,
                )
            except BleakError as exc:
                console.print(f"[red]BLE error: {exc}[/red]")
                if "Peer removed" in str(exc) or "Code=14" in str(exc):
                    from oura_ble import peer_removed_pairing_help

                    console.print(f"\n[yellow]{peer_removed_pairing_help()}[/yellow]")
                sys.exit(1)

        rx = [
            e
            for e in events
            if e["direction"] == "RX"
            and e.get("hex")
            and not all(c == "0" for c in e["hex"])
        ]
        console.print(f"\n[bold]Done — {len(rx)} non-zero RX event(s), log at {output}[/bold]")

    asyncio.run(_run())


if __name__ == "__main__":
    main()
