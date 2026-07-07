#!/usr/bin/env python3
"""Read battery level from Oura Ring via authenticated BLE command."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import click
from bleak.exc import BleakError
from rich.console import Console

from oura_ble import authenticate, close_session, open_session, transact
from oura_protocol import CMD_BATTERY, parse_packet
from scan_oura import discover_oura_devices, print_discovered

console = Console()


def load_key(path: Path) -> bytes:
    key = bytes.fromhex(path.read_text(encoding="utf-8").strip())
    if len(key) != 16:
        raise click.ClickException("auth key must be 16 bytes (32 hex chars)")
    return key


@click.command()
@click.option("--timeout", "-t", default=15.0, show_default=True)
@click.option("--connect-timeout", default=30.0, show_default=True)
@click.option("--address", "-a", default=None)
@click.option(
    "--key-file",
    "-k",
    type=click.Path(exists=True, path_type=Path),
    default=Path("key.hex"),
    show_default=True,
)
def main(timeout: float, connect_timeout: float, address: str | None, key_file: Path) -> None:
    """Authenticate and read battery % (Oura tag 0x0D)."""

    async def _run() -> None:
        key = load_key(key_file)

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

        client, queue = await open_session(target, connect_timeout=connect_timeout)
        try:
            if not await authenticate(client, queue, key):
                console.print("[red]Authentication failed — check key.hex[/red]")
                sys.exit(1)

            responses = await transact(client, queue, CMD_BATTERY)
            for resp in responses:
                parsed = parse_packet(resp)
                if "battery_percent" in parsed:
                    pct = parsed["battery_percent"]
                    charging = parsed.get("charging_progress")
                    console.print(f"[bold green]Battery: {pct}%[/bold green]")
                    if charging is not None:
                        console.print(f"Charging progress: {charging}")
                    return

            console.print("[yellow]No battery response. Try probe_oura.py for full trace.[/yellow]")
            sys.exit(1)
        finally:
            await close_session(client)

    try:
        asyncio.run(_run())
    except BleakError as exc:
        console.print(f"[red]BLE error: {exc}[/red]")
        sys.exit(1)


if __name__ == "__main__":
    main()
