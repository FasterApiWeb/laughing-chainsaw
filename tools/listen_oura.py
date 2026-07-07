#!/usr/bin/env python3
"""Connect to Oura Ring and print live GATT notifications (hex payloads)."""

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

from scan_oura import discover_oura_devices, lookup_uuid, print_discovered

console = Console()

NOTIFY_PROPERTIES = frozenset({"notify", "indicate"})
DATA_CHAR = "98ed0003-a541-11e4-b6a0-0002a5d5c51b"


def short_uuid_label(uuid: str) -> str:
    prefix = uuid.replace("-", "")[:8].lower()
    if prefix.startswith("98ed"):
        return f"98ed:{prefix[4:8]}"
    if prefix.startswith("000600"):
        return f"aux:{prefix[4:8]}"
    return uuid[:8]


async def listen(
    device: BLEDevice,
    *,
    connect_timeout: float,
    duration: float | None,
    output: Path | None,
    auth_key: bytes | None,
) -> None:
    events: list[dict[str, Any]] = []
    output_handle: Any = None
    cmd_queue: asyncio.Queue[bytes] | None = (
        asyncio.Queue() if auth_key else None
    )

    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output_handle = output.open("a", encoding="utf-8")

    def make_handler(char_uuid: str, handle: int):
        label = short_uuid_label(char_uuid)

        def on_notify(_handle: int, data: bytearray) -> None:
            if char_uuid == DATA_CHAR and cmd_queue is not None:
                cmd_queue.put_nowait(bytes(data))
            entry = {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "handle": handle,
                "uuid": char_uuid,
                "label": label,
                "length": len(data),
                "hex": data.hex(),
            }
            events.append(entry)
            console.print(
                f"[cyan]{entry['timestamp']}[/cyan] "
                f"[bold]{label}[/bold] h={handle} "
                f"len={entry['length']} "
                f"[green]{entry['hex'][:64]}{'…' if len(entry['hex']) > 64 else ''}[/green]"
            )
            if output_handle:
                output_handle.write(json.dumps(entry) + "\n")
                output_handle.flush()

        return on_notify

    async with BleakClient(device, timeout=connect_timeout) as client:
        notify_chars: list[tuple[str, int]] = []

        for service in client.services:
            for char in service.characteristics:
                if NOTIFY_PROPERTIES & set(char.properties):
                    notify_chars.append((char.uuid, char.handle))

        if not notify_chars:
            console.print("[yellow]No notify/indicate characteristics found.[/yellow]")
            return

        console.print(
            f"[bold]Connected[/bold] (MTU {client.mtu_size}). "
            f"Subscribing to {len(notify_chars)} characteristic(s)…"
        )
        for uuid, handle in notify_chars:
            info = lookup_uuid(uuid)
            console.print(f"  • h={handle} {short_uuid_label(uuid)} ({info['sig_name']})")

        for uuid, handle in notify_chars:
            await client.start_notify(uuid, make_handler(uuid, handle))

        if auth_key and cmd_queue is not None:
            from oura_ble import authenticate, transact
            from oura_protocol import CMD_BATTERY, CMD_FIRMWARE, CMD_SET_NOTIFICATION

            if await authenticate(client, cmd_queue, auth_key):
                console.print("[bold green]Authenticated[/bold green] — enabling notifications…")
                for name, req in (
                    ("set_notification", CMD_SET_NOTIFICATION),
                    ("firmware", CMD_FIRMWARE),
                    ("battery", CMD_BATTERY),
                ):
                    await transact(client, cmd_queue, req)
                    console.print(f"  sent {name}")
            else:
                console.print("[yellow]Auth failed — listening without commands.[/yellow]")

        console.print("[bold green]Listening[/bold green] — Ctrl+C to stop.")
        if duration:
            await asyncio.sleep(duration)
        else:
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                pass

        for uuid, _handle in notify_chars:
            try:
                await client.stop_notify(uuid)
            except BleakError:
                pass

    if output_handle:
        output_handle.close()

    console.print(f"[bold]Captured {len(events)} notification(s).[/bold]")


@click.command()
@click.option("--timeout", "-t", default=10.0, show_default=True, help="Scan duration (seconds).")
@click.option("--connect-timeout", default=30.0, show_default=True)
@click.option("--address", "-a", default=None, help="CoreBluetooth UUID from scan_oura.py.")
@click.option(
    "--duration",
    "-d",
    default=None,
    type=float,
    help="Stop after N seconds (default: run until Ctrl+C).",
)
@click.option(
    "--output",
    "-o",
    type=click.Path(path_type=Path),
    default=Path("captures/ble/notifications.jsonl"),
    show_default=True,
    help="Append JSONL log (pass /dev/null style omit with -o - to disable).",
)
@click.option(
    "--key-file",
    "-k",
    type=click.Path(path_type=Path),
    default=None,
    help="Authenticate and send enable commands before listening.",
)
def main(
    timeout: float,
    connect_timeout: float,
    address: str | None,
    duration: float | None,
    output: Path,
    key_file: Path | None,
) -> None:
    """Subscribe to Oura Ring GATT notifications and print hex payloads."""
    out_path = None if str(output) == "-" else output

    async def _run() -> None:
        auth_key: bytes | None = None
        if key_file:
            if not key_file.exists():
                console.print(f"[red]Missing {key_file}[/red]")
                sys.exit(1)
            auth_key = bytes.fromhex(key_file.read_text(encoding="utf-8").strip())
            if len(auth_key) != 16:
                console.print("[red]key must be 16 bytes (32 hex chars)[/red]")
                sys.exit(1)

        console.print(f"[bold]Scanning for Oura devices ({timeout:.0f}s)...[/bold]")
        devices = await discover_oura_devices(timeout)
        print_discovered(devices)
        if not devices:
            sys.exit(1)

        if address:
            matches = [d for d, _a in devices if d.address == address]
            if not matches:
                console.print(f"[red]No device matches {address!r}.[/red]")
                sys.exit(1)
            target = matches[0]
        else:
            target = devices[0][0]

        name = target.name or target.address
        console.print(f"[bold]Connecting to {name} ({target.address})...[/bold]")
        try:
            await listen(
                target,
                connect_timeout=connect_timeout,
                duration=duration,
                output=out_path,
                auth_key=auth_key,
            )
        except BleakError as exc:
            console.print(f"[red]BLE error: {exc}[/red]")
            sys.exit(1)

    try:
        asyncio.run(_run())
    except KeyboardInterrupt:
        console.print("\n[yellow]Stopped.[/yellow]")


if __name__ == "__main__":
    main()
