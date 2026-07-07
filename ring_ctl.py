#!/usr/bin/env python3
"""
Authenticated ring control: factory reset and related danger ops.

Requires key.hex from a successful pair_oura.py session.
"""

from __future__ import annotations

import asyncio
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import click
from bleak.exc import BleakError
from rich.console import Console

from oura_ble import authenticate, close_session, open_session, transact
from oura_protocol import CMD_FACTORY_RESET, describe_packet, parse_packet
from scan_oura import discover_oura_devices, print_discovered

console = Console()


def load_key(path: Path) -> bytes:
    if not path.exists():
        raise click.ClickException(f"Missing key file: {path}")
    key = bytes.fromhex(path.read_text(encoding="utf-8").strip())
    if len(key) != 16:
        raise click.ClickException("auth key must be 16 bytes (32 hex chars)")
    return key


def log_step(msg: str, data: bytes | None = None) -> None:
    extra = f" — {data.hex()}" if data else ""
    parsed = describe_packet(data) if data else ""
    console.print(f"[bold]{msg}[/bold]{extra}" + (f" [dim]({parsed})[/dim]" if parsed else ""))


async def factory_reset_device(
    device: Any,
    *,
    key: bytes,
    connect_timeout: float,
) -> dict[str, Any]:
    result: dict[str, Any] = {"address": device.address}

    client, queue = await open_session(device, connect_timeout=connect_timeout)
    try:
        if not await authenticate(client, queue, key, log=log_step):
            result["error"] = "Authentication failed — wrong key or ring not paired with this key"
            return result

        result["authenticated"] = True
        log_step("TX FactoryReset (0x1a)")
        responses = await transact(client, queue, CMD_FACTORY_RESET, wait=5.0)
        for resp in responses:
            parsed = parse_packet(resp)
            if "factory_reset_status" in parsed:
                result["factory_reset_status"] = parsed["factory_reset_status"]
                log_step("RX FactoryReset", resp)
            else:
                log_step("RX", resp)

        if "factory_reset_status" not in result and not responses:
            # Ring may reset before responding; treat as likely success.
            result["factory_reset_status"] = None
            result["note"] = "No response frame — ring may have reset immediately"

        result["factory_reset_sent"] = True
    finally:
        await close_session(client)

    return result


@click.group()
def main() -> None:
    """Authenticated Oura ring control (requires key.hex)."""


@main.command("factory-reset")
@click.option("--timeout", "-t", default=20.0, show_default=True)
@click.option("--connect-timeout", default=30.0, show_default=True)
@click.option("--address", "-a", default=None)
@click.option(
    "--key-file",
    "-k",
    type=click.Path(path_type=Path),
    default=Path("key.hex"),
    show_default=True,
)
@click.confirmation_option(
    prompt="Factory reset ERASES all ring data and auth keys. Continue?",
)
def factory_reset_cmd(
    timeout: float,
    connect_timeout: float,
    address: str | None,
    key_file: Path,
) -> None:
    """Authenticate with key.hex then send BLE factory reset (tag 0x1a)."""

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

        console.print(f"[bold]Factory reset via {target.name or target.address}…[/bold]\n")

        try:
            outcome = await factory_reset_device(
                target,
                key=key,
                connect_timeout=connect_timeout,
            )
        except BleakError as exc:
            console.print(f"[red]BLE error:[/red]\n{exc}")
            sys.exit(1)

        log_path = Path("captures/ble/factory_reset.json")
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(
            json.dumps(
                {"generated_at": datetime.now(timezone.utc).isoformat(), **outcome},
                indent=2,
            )
        )

        if outcome.get("factory_reset_sent"):
            console.print("\n[bold yellow]Factory reset command sent.[/bold yellow]")
            console.print(
                "Next steps:\n"
                "  1. Forget the ring in macOS Bluetooth settings (avoids CBError 14)\n"
                "  2. Ring on charger; force-quit Oura app on iPhone\n"
                "  3. python scan_oura.py  # note new address if it changed\n"
                "  4. python pair_oura.py   # install a fresh key.hex"
            )
        else:
            console.print(f"\n[red]Failed:[/red] {outcome.get('error', 'unknown')}")
            sys.exit(1)

    asyncio.run(_run())


if __name__ == "__main__":
    main()
