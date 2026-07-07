#!/usr/bin/env python3
"""
BLE pairing / bonding analysis for Oura Ring on macOS.

Oura uses application-layer auth (SetAuthKey + AES), not classic BLE passkey
pairing for data access. This script documents what bleak/macOS actually do
when you connect and optionally call pair().
"""

from __future__ import annotations

import asyncio
import sys

import click
from bleak import BleakClient
from bleak.exc import BleakError
from rich.console import Console
from rich.table import Table

from scan_oura import discover_oura_devices, print_discovered

console = Console()


async def analyze(device, *, connect_timeout: float, try_pair: bool) -> dict:
    result: dict = {
        "address": device.address,
        "name": device.name,
        "connected": False,
        "is_paired": None,
        "pair_attempted": try_pair,
        "pair_succeeded": None,
        "service_count": 0,
        "notes": [],
    }

    client = BleakClient(device, timeout=connect_timeout, pair=try_pair)
    try:
        await client.connect()
        result["connected"] = True

        if hasattr(client, "is_paired"):
            try:
                result["is_paired"] = await client.is_paired()
            except Exception as exc:  # noqa: BLE001 — platform-specific
                result["notes"].append(f"is_paired() failed: {exc}")

        if try_pair and hasattr(client, "pair"):
            try:
                result["pair_succeeded"] = await client.pair()
            except BleakError as exc:
                result["pair_succeeded"] = False
                result["notes"].append(f"pair() failed: {exc}")

        services = client.services
        result["service_count"] = len(list(services))

    finally:
        if client.is_connected:
            await client.disconnect()

    result["notes"].append(
        "Oura data access uses 98ed0002/0003 app-auth (pair_oura.py), "
        "not standard BLE battery service reads."
    )
    return result


@click.command()
@click.option("--timeout", "-t", default=15.0, show_default=True)
@click.option("--connect-timeout", default=30.0, show_default=True)
@click.option("--address", "-a", default=None)
@click.option("--try-pair", is_flag=True, default=False, help="Call BleakClient.pair().")
def main(timeout: float, connect_timeout: float, address: str | None, try_pair: bool) -> None:
    """Connect to Oura Ring and report BLE pairing state."""

    async def _run() -> None:
        devices = await discover_oura_devices(timeout)
        print_discovered(devices)
        if not devices:
            sys.exit(1)

        target = (
            next(d for d, _ in devices if d.address == address)
            if address
            else devices[0][0]
        )

        console.print(f"[bold]Analyzing {target.name or target.address}…[/bold]\n")
        try:
            outcome = await analyze(target, connect_timeout=connect_timeout, try_pair=try_pair)
        except BleakError as exc:
            console.print(f"[red]BLE error: {exc}[/red]")
            sys.exit(1)

        table = Table(title="Pairing analysis")
        for key, value in outcome.items():
            if key != "notes":
                table.add_row(key, str(value))
        console.print(table)
        for note in outcome["notes"]:
            console.print(f"[dim]• {note}[/dim]")

    asyncio.run(_run())


if __name__ == "__main__":
    main()
