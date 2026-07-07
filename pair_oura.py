#!/usr/bin/env python3
"""
Pair a factory-reset Oura Ring with a new auth key (cloud-free).

Protocol from open_oura + ringverse/protocol:
  1. SetAuthKey (0x24) — install 16-byte key on factory-reset ring
  2. GetAuthNonce (2f012b) + Authenticate (2f112d…) — prove key works
  3. sync time, enable notifications, turn on HR/SpO2 features

After pairing, factory-reset from Mac: ring_ctl.py factory-reset --key-file key.hex
"""

from __future__ import annotations

import asyncio
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import click
from bleak.exc import BleakError
from rich.console import Console

from oura_ble import close_session, open_session, peer_removed_pairing_help, transact
from oura_protocol import (
    CMD_BATTERY,
    CMD_SET_NOTIFICATION,
    FEATURE_DAYTIME_HR,
    FEATURE_MODE_AUTOMATIC,
    FEATURE_SPO2,
    authenticate_request,
    describe_packet,
    extract_auth_nonce,
    generate_auth_key,
    parse_packet,
    set_auth_key_request,
    set_feature_mode_request,
    sync_time_request,
)
from scan_oura import discover_oura_devices, print_discovered

console = Console()

CMD_AUTH_NONCE = bytes.fromhex("2f012b")


def save_key(path: Path, key: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(key.hex() + "\n", encoding="utf-8")
    path.chmod(0o600)


def log_step(msg: str, data: bytes | None = None) -> None:
    extra = f" — {data.hex()}" if data else ""
    parsed = describe_packet(data) if data else ""
    console.print(f"[bold]{msg}[/bold]{extra}" + (f" [dim]({parsed})[/dim]" if parsed else ""))


async def pair_device(
    device: Any,
    *,
    key: bytes,
    connect_timeout: float,
    enable_features: bool,
) -> dict[str, Any]:
    result: dict[str, Any] = {"address": device.address, "key_hex": key.hex()}

    client, queue = await open_session(device, connect_timeout=connect_timeout)
    try:
        log_step("TX SetAuthKey")
        set_responses = await transact(client, queue, set_auth_key_request(key))
        set_ok = False
        for resp in set_responses:
            parsed = parse_packet(resp)
            status = parsed.get("set_auth_key_status")
            if status == 0:
                set_ok = True
                log_step("RX SetAuthKey OK", resp)
            elif status is not None:
                result["set_auth_key_error"] = status
                log_step(f"RX SetAuthKey failed status=0x{status:02x}", resp)

        if not set_ok:
            result["error"] = (
                "SetAuthKey failed. Ring must be factory-reset (Oura app or "
                "ring_ctl.py factory-reset) and Mac Bluetooth must forget the old bond."
            )
            return result

        log_step("TX GetAuthNonce")
        nonce_responses = await transact(client, queue, CMD_AUTH_NONCE)
        nonce: bytes | None = None
        for resp in nonce_responses:
            nonce = extract_auth_nonce(resp)
            if nonce:
                log_step("RX nonce", resp)
                break

        if not nonce:
            result["error"] = "No auth nonce after SetAuthKey"
            return result

        auth_req = authenticate_request(key, nonce)
        log_step("TX Authenticate")
        auth_responses = await transact(client, queue, auth_req)
        authed = False
        for resp in auth_responses:
            parsed = parse_packet(resp)
            state = parsed.get("auth_state_name")
            log_step(f"RX auth {state}", resp)
            if state == "success":
                authed = True

        if not authed:
            result["error"] = "Authenticate failed after SetAuthKey"
            return result

        result["authenticated"] = True

        log_step("TX sync_time")
        await transact(client, queue, sync_time_request(int(time.time())))

        log_step("TX set_notification")
        await transact(client, queue, CMD_SET_NOTIFICATION)

        if enable_features:
            for feature, name in (
                (FEATURE_DAYTIME_HR, "daytime_hr"),
                (FEATURE_SPO2, "spo2"),
            ):
                req = set_feature_mode_request(feature, FEATURE_MODE_AUTOMATIC)
                log_step(f"TX enable {name}")
                await transact(client, queue, req)

        log_step("TX battery")
        bat_responses = await transact(client, queue, CMD_BATTERY)
        for resp in bat_responses:
            parsed = parse_packet(resp)
            if "battery_percent" in parsed:
                result["battery_percent"] = parsed["battery_percent"]
                log_step(f"RX battery {parsed['battery_percent']}%", resp)
    finally:
        await close_session(client)

    return result


@click.command()
@click.option("--timeout", "-t", default=20.0, show_default=True)
@click.option("--connect-timeout", default=30.0, show_default=True)
@click.option("--address", "-a", default=None, help="Omit if CBError 14 — use fresh scan address.")
@click.option(
    "--key-file",
    "-k",
    type=click.Path(path_type=Path),
    default=Path("key.hex"),
    show_default=True,
)
@click.option("--use-existing-key", is_flag=True, default=False)
@click.option("--no-enable-features", is_flag=True, default=False)
@click.confirmation_option(
    prompt="Ring must be factory-reset. This installs a NEW auth key. Continue?",
)
def main(
    timeout: float,
    connect_timeout: float,
    address: str | None,
    key_file: Path,
    use_existing_key: bool,
    no_enable_features: bool,
) -> None:
    """Pair a factory-reset Oura Ring for cloud-free BLE access."""

    async def _run() -> None:
        if use_existing_key:
            if not key_file.exists():
                console.print(f"[red]Missing {key_file}[/red]")
                sys.exit(1)
            key = bytes.fromhex(key_file.read_text(encoding="utf-8").strip())
        else:
            key = generate_auth_key()

        console.print(
            "[dim]If you get CBError 14, forget the ring in System Settings → "
            "Bluetooth first.[/dim]\n"
        )

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

        console.print(f"[bold]Pairing with {target.name or target.address}…[/bold]")
        console.print(f"[dim]Key (preview): {key.hex()[:16]}…[/dim]\n")

        try:
            outcome = await pair_device(
                target,
                key=key,
                connect_timeout=connect_timeout,
                enable_features=not no_enable_features,
            )
        except BleakError as exc:
            console.print(f"[red]BLE error:[/red]\n{exc}")
            if "CBError 14" not in str(exc):
                console.print(f"\n[yellow]{peer_removed_pairing_help()}[/yellow]")
            sys.exit(1)

        log_path = Path("captures/ble/pair.json")
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(
            json.dumps(
                {"generated_at": datetime.now(timezone.utc).isoformat(), **outcome},
                indent=2,
            )
        )

        if outcome.get("authenticated"):
            save_key(key_file, key)
            console.print("\n[bold green]Paired successfully.[/bold green]")
            console.print(f"Key saved → [cyan]{key_file}[/cyan]")
            console.print(
                f"\n  python probe_oura.py --key-file {key_file}\n"
                f"  python ring_ctl.py factory-reset --key-file {key_file}  # later, if needed"
            )
            if outcome.get("battery_percent") is not None:
                console.print(f"Battery: {outcome['battery_percent']}%")
        else:
            console.print(f"\n[red]Pairing failed:[/red] {outcome.get('error', 'unknown')}")
            console.print(f"\n[yellow]{peer_removed_pairing_help()}[/yellow]")
            sys.exit(1)

    asyncio.run(_run())


if __name__ == "__main__":
    main()
