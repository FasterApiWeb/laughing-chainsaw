#!/usr/bin/env python3
"""LibreRing recon: discover Oura Ring BLE devices and dump GATT to JSON."""

from __future__ import annotations

import asyncio
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import click
from bleak import BleakClient, BleakScanner
from bleak.backends._manufacturers import MANUFACTURERS
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData
from bleak.exc import BleakError, BleakGATTProtocolError
from bleak.uuids import normalize_uuid_str, uuidstr_to_str
from rich.console import Console
from rich.table import Table

# JouZen Oy (Oura Health) — Bluetooth SIG company identifier 0x02B2
OURA_MANUFACTURER_ID = 0x02B2

# Known Oura GATT service UUID prefixes (128-bit vendor services)
OURA_SERVICE_PREFIXES = (
    "98ed",  # Ring primary service
    "8bc5",  # Charging case service
)

BLUETOOTH_BASE_SUFFIX = "-0000-1000-8000-00805f9b34fb"

console = Console()


def bytes_to_hex(data: bytes | bytearray | None) -> str | None:
    if data is None:
        return None
    return data.hex()


def lookup_company_id(company_id: int) -> dict[str, Any]:
    name = MANUFACTURERS.get(company_id)
    return {
        "id": f"0x{company_id:04X}",
        "id_decimal": company_id,
        "name": name or "Unknown",
        "sig_assigned": name is not None,
    }


def lookup_uuid(uuid_str: str) -> dict[str, Any]:
    """Resolve a UUID against Bluetooth SIG assigned numbers via bleak."""
    normalized = normalize_uuid_str(uuid_str)
    sig_name = uuidstr_to_str(normalized)
    short_uuid: str | None = None
    is_sig_assigned = sig_name not in ("Unknown", "Vendor specific")

    if normalized.endswith(BLUETOOTH_BASE_SUFFIX):
        short_uuid = f"0x{normalized[4:8].upper()}"

    return {
        "uuid": normalized,
        "short_uuid": short_uuid,
        "sig_name": sig_name,
        "sig_assigned": is_sig_assigned,
    }


def is_oura_device(_device: BLEDevice, adv: AdvertisementData) -> bool:
    name = (adv.local_name or _device.name or "").strip().lower()
    if "oura" in name:
        return True

    if OURA_MANUFACTURER_ID in adv.manufacturer_data:
        return True

    for service_uuid in adv.service_uuids:
        prefix = service_uuid.replace("-", "")[:4].lower()
        if prefix in OURA_SERVICE_PREFIXES:
            return True

    return False


def device_summary(device: BLEDevice, adv: AdvertisementData | None) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "name": (adv.local_name if adv else None) or device.name,
        "address": device.address,
        "rssi": adv.rssi if adv else None,
    }

    if adv and adv.manufacturer_data:
        summary["manufacturer_data"] = [
            {
                **lookup_company_id(company_id),
                "payload_hex": payload.hex(),
            }
            for company_id, payload in adv.manufacturer_data.items()
        ]

    if adv and adv.service_uuids:
        summary["advertised_services"] = [
            lookup_uuid(uuid) for uuid in adv.service_uuids
        ]

    return summary


async def discover_oura_devices(timeout: float) -> list[tuple[BLEDevice, AdvertisementData]]:
    seen: dict[str, tuple[BLEDevice, AdvertisementData]] = {}

    def on_detect(device: BLEDevice, adv: AdvertisementData) -> None:
        if is_oura_device(device, adv):
            seen[device.address] = (device, adv)

    scanner = BleakScanner(detection_callback=on_detect)
    await scanner.start()
    try:
        await asyncio.sleep(timeout)
    finally:
        await scanner.stop()

    return list(seen.values())


def print_discovered(devices: list[tuple[BLEDevice, AdvertisementData]]) -> None:
    if not devices:
        console.print("[yellow]No Oura devices found.[/yellow]")
        console.print(
            "Ensure the ring is awake (on charger), Bluetooth is enabled, "
            "and no other host is connected."
        )
        return

    table = Table(title="Discovered Oura BLE Devices")
    table.add_column("#", style="dim")
    table.add_column("Name")
    table.add_column("Address")
    table.add_column("RSSI")
    table.add_column("Manufacturer")

    for index, (device, adv) in enumerate(devices, start=1):
        mfg = adv.manufacturer_data.get(OURA_MANUFACTURER_ID)
        mfg_label = lookup_company_id(OURA_MANUFACTURER_ID)["name"] if mfg else "-"
        table.add_row(
            str(index),
            (adv.local_name or device.name or "?"),
            device.address,
            str(adv.rssi) if adv.rssi is not None else "?",
            mfg_label,
        )

    console.print(table)


async def read_if_allowed(
    client: BleakClient,
    *,
    read_values: bool,
    readable: bool,
    reader: Any,
) -> dict[str, Any] | None:
    if not read_values or not readable:
        return None

    try:
        value = await reader()
        return {"hex": bytes_to_hex(value), "length": len(value)}
    except (BleakError, BleakGATTProtocolError, OSError) as exc:
        return {"error": str(exc)}


async def dump_gatt(
    client: BleakClient,
    *,
    read_values: bool,
) -> list[dict[str, Any]]:
    services_out: list[dict[str, Any]] = []

    for service in client.services:
        service_entry: dict[str, Any] = {
            "handle": service.handle,
            **lookup_uuid(service.uuid),
            "characteristics": [],
        }

        for char in service.characteristics:
            char_entry: dict[str, Any] = {
                "handle": char.handle,
                **lookup_uuid(char.uuid),
                "properties": list(char.properties),
                "max_write_without_response_size": char.max_write_without_response_size,
                "value": await read_if_allowed(
                    client,
                    read_values=read_values,
                    readable="read" in char.properties,
                    reader=lambda c=char: client.read_gatt_char(c),
                ),
                "descriptors": [],
            }

            for desc in char.descriptors:
                desc_entry: dict[str, Any] = {
                    "handle": desc.handle,
                    **lookup_uuid(desc.uuid),
                    "description": desc.description,
                    "value": await read_if_allowed(
                        client,
                        read_values=read_values,
                        readable=True,
                        reader=lambda d=desc: client.read_gatt_descriptor(d),
                    ),
                }
                char_entry["descriptors"].append(desc_entry)

            service_entry["characteristics"].append(char_entry)

        services_out.append(service_entry)

    return services_out


async def dump_device(
    device: BLEDevice,
    adv: AdvertisementData | None,
    *,
    read_values: bool,
    connect_timeout: float,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "device": device_summary(device, adv),
        "connected": False,
        "services": [],
    }

    async with BleakClient(device, timeout=connect_timeout) as client:
        result["connected"] = True
        result["mtu_size"] = client.mtu_size
        result["services"] = await dump_gatt(client, read_values=read_values)

    return result


async def run(
    *,
    timeout: float,
    connect_timeout: float,
    address: str | None,
    output: Path,
    read_values: bool,
    all_devices: bool,
) -> None:
    console.print(f"[bold]Scanning for Oura devices ({timeout:.0f}s)...[/bold]")
    devices = await discover_oura_devices(timeout)
    print_discovered(devices)

    if not devices:
        sys.exit(1)

    if address:
        matches = [(d, a) for d, a in devices if d.address == address]
        if not matches:
            console.print(f"[red]No discovered device matches address {address!r}.[/red]")
            sys.exit(1)
        targets = matches
    elif all_devices:
        targets = devices
    else:
        targets = [devices[0]]

    dump: dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "oura_manufacturer": lookup_company_id(OURA_MANUFACTURER_ID),
        "scan_timeout_seconds": timeout,
        "read_values": read_values,
        "devices": [],
    }

    for device, adv in targets:
        name = (adv.local_name or device.name or device.address)
        console.print(f"[bold]Connecting to {name} ({device.address})...[/bold]")
        try:
            device_dump = await dump_device(
                device,
                adv,
                read_values=read_values,
                connect_timeout=connect_timeout,
            )
            dump["devices"].append(device_dump)
            service_count = len(device_dump["services"])
            char_count = sum(len(s["characteristics"]) for s in device_dump["services"])
            desc_count = sum(
                len(c["descriptors"])
                for s in device_dump["services"]
                for c in s["characteristics"]
            )
            console.print(
                f"[green]OK[/green] — {service_count} services, "
                f"{char_count} characteristics, {desc_count} descriptors"
            )
        except BleakError as exc:
            console.print(f"[red]Failed to connect to {name}: {exc}[/red]")
            dump["devices"].append(
                {
                    "device": device_summary(device, adv),
                    "connected": False,
                    "error": str(exc),
                    "services": [],
                }
            )

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(dump, indent=2))
    console.print(f"[bold green]Wrote GATT dump to {output}[/bold green]")


@click.command()
@click.option(
    "--timeout",
    "-t",
    default=10.0,
    show_default=True,
    help="Seconds to scan for Oura devices.",
)
@click.option(
    "--connect-timeout",
    default=30.0,
    show_default=True,
    help="Seconds to wait when connecting to a device.",
)
@click.option(
    "--address",
    "-a",
    default=None,
    help="Connect to a specific device address (macOS: CoreBluetooth UUID).",
)
@click.option(
    "--output",
    "-o",
    type=click.Path(path_type=Path),
    default=Path("services.json"),
    show_default=True,
    help="Output JSON file path.",
)
@click.option(
    "--read-values",
    is_flag=True,
    default=False,
    help="Attempt to read characteristic and descriptor values (may require pairing).",
)
@click.option(
    "--all",
    "all_devices",
    is_flag=True,
    default=False,
    help="Dump all discovered Oura devices instead of only the first.",
)
def main(
    timeout: float,
    connect_timeout: float,
    address: str | None,
    output: Path,
    read_values: bool,
    all_devices: bool,
) -> None:
    """Discover Oura Ring BLE devices and dump GATT services to JSON."""
    asyncio.run(
        run(
            timeout=timeout,
            connect_timeout=connect_timeout,
            address=address,
            output=output,
            read_values=read_values,
            all_devices=all_devices,
        )
    )


if __name__ == "__main__":
    main()
