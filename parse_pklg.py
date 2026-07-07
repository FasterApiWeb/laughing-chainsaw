#!/usr/bin/env python3
"""
Extract a BLE ATT/GATT timeline from an Apple PacketLogger .pklg capture.

Uses tshark (from Wireshark) to decode HCI → L2CAP → ATT layers, then writes
a JSON timeline of read/write/notify operations.

Requires: brew install wireshark

Usage:
    python parse_pklg.py capture.pklg
    python parse_pklg.py capture.pklg -o timeline.json
    python parse_pklg.py capture.pklg --oura-only
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import click
from rich.console import Console

# Handles from services.json (Oura Ring 4) — update after re-scanning
OURA_HANDLES: dict[int, str] = {
    16: "98ed0001 service",
    17: "98ed0003 data_rx",
    19: "2902 cccd",
    20: "98ed0002 cmd_tx",
    22: "98ed0004 data_ext",
    24: "2902 cccd",
    25: "98ed0005 notify_a",
    27: "2902 cccd",
    28: "98ed0006 notify_b",
    30: "2902 cccd",
    31: "00060000 aux_service",
    32: "00060001 aux_channel",
    34: "2902 cccd",
}

ATT_OPCODE_NAMES: dict[int, str] = {
    0x01: "error_response",
    0x02: "exchange_mtu_req",
    0x03: "exchange_mtu_rsp",
    0x0A: "read_req",
    0x0B: "read_rsp",
    0x12: "write_req",
    0x13: "write_rsp",
    0x1B: "notification",
    0x1D: "indication",
    0x52: "write_cmd",
}

console = Console()


def require_tshark() -> str:
    tshark = shutil.which("tshark")
    if not tshark:
        console.print(
            "[red]tshark not found.[/red] Install Wireshark:\n"
            "  brew install --cask wireshark\n"
            "Then add tshark to PATH (Wireshark installer prompts for this)."
        )
        sys.exit(1)
    return tshark


def run_tshark_json(tshark: str, pklg: Path) -> list[dict[str, Any]]:
    cmd = [
        tshark,
        "-r",
        str(pklg),
        "-Y",
        "btatt",
        "-T",
        "json",
        "-n",
    ]
    console.print(f"[dim]Running: {' '.join(cmd)}[/dim]")
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        console.print(f"[red]tshark failed:[/red]\n{result.stderr}")
        sys.exit(1)
    if not result.stdout.strip():
        return []
    return json.loads(result.stdout)


def extract_layers(packet: dict[str, Any]) -> dict[str, Any] | None:
    layers = packet.get("_source", {}).get("layers", {})
    btatt = layers.get("btatt")
    if not btatt:
        return None

    frame = layers.get("frame", {})
    time_epoch = frame.get("frame.time_epoch")
    number = frame.get("frame.number")

    opcode_raw = btatt.get("btatt.opcode")
    handle_raw = btatt.get("btatt.handle")
    value_raw = btatt.get("btatt.value")

    if opcode_raw is None:
        return None

    try:
        opcode = int(opcode_raw, 0) if isinstance(opcode_raw, str) else int(opcode_raw)
    except (TypeError, ValueError):
        return None

    handle: int | None = None
    if handle_raw is not None:
        try:
            handle = int(handle_raw, 0) if isinstance(handle_raw, str) else int(handle_raw)
        except (TypeError, ValueError):
            handle = None

    payload_hex: str | None = None
    if value_raw is not None:
        if isinstance(value_raw, list):
            payload_hex = ":".join(value_raw)
        else:
            payload_hex = str(value_raw).replace(":", "")

    return {
        "frame": int(number) if number else None,
        "time_epoch": float(time_epoch) if time_epoch else None,
        "opcode": opcode,
        "opcode_name": ATT_OPCODE_NAMES.get(opcode, f"0x{opcode:02x}"),
        "handle": handle,
        "oura_label": OURA_HANDLES.get(handle) if handle is not None else None,
        "payload_hex": payload_hex,
    }


def build_timeline(packets: list[dict[str, Any]], oura_only: bool) -> dict[str, Any]:
    events: list[dict[str, Any]] = []
    for packet in packets:
        event = extract_layers(packet)
        if event is None:
            continue
        if oura_only and event["oura_label"] is None:
            continue
        events.append(event)

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "event_count": len(events),
        "oura_only": oura_only,
        "events": events,
    }


@click.command()
@click.argument("pklg", type=click.Path(exists=True, path_type=Path))
@click.option(
    "-o",
    "--output",
    type=click.Path(path_type=Path),
    default=None,
    help="Output JSON path (default: <pklg>.timeline.json)",
)
@click.option(
    "--oura-only",
    is_flag=True,
    default=False,
    help="Keep only ATT events on known Oura GATT handles.",
)
def main(pklg: Path, output: Path | None, oura_only: bool) -> None:
    """Parse a PacketLogger .pklg file into an ATT/GATT operation timeline."""
    tshark = require_tshark()
    packets = run_tshark_json(tshark, pklg)
    timeline = build_timeline(packets, oura_only)

    out = output or pklg.with_suffix(".timeline.json")
    out.write_text(json.dumps(timeline, indent=2))

    console.print(
        f"[green]Wrote {timeline['event_count']} ATT events → {out}[/green]"
    )
    if timeline["event_count"] == 0:
        console.print(
            "[yellow]No btatt packets found. Ensure the capture includes BLE traffic "
            "and Wireshark can read the .pklg format.[/yellow]"
        )


if __name__ == "__main__":
    main()
