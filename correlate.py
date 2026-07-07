#!/usr/bin/env python3
"""Correlate mitmproxy API captures with BLE packet timelines by timestamp."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import click
from rich.console import Console
from rich.table import Table

console = Console()


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


def load_timeline(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("events", data if isinstance(data, list) else [])


def parse_ts(value: str | float | None) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def correlate(
    api_events: list[dict[str, Any]],
    ble_events: list[dict[str, Any]],
    *,
    window_seconds: float,
) -> list[dict[str, Any]]:
    ble_ts = [
        (parse_ts(e.get("timestamp") or e.get("time_epoch")), e)
        for e in ble_events
    ]
    ble_ts = [(t, e) for t, e in ble_ts if t is not None]

    matches: list[dict[str, Any]] = []
    for api in api_events:
        api_time = parse_ts(api.get("timestamp"))
        if api_time is None:
            continue

        nearby = [
            ble
            for t, ble in ble_ts
            if abs(t - api_time) <= window_seconds
        ]
        if not nearby:
            continue

        matches.append(
            {
                "api_timestamp": api.get("timestamp"),
                "api_path": api.get("path") or api.get("url"),
                "api_method": api.get("method"),
                "ble_event_count": len(nearby),
                "ble_events": nearby[:5],
            }
        )

    return matches


@click.command()
@click.option(
    "--api",
    "api_path",
    type=click.Path(exists=True, path_type=Path),
    required=True,
    help="mitmproxy JSONL from capture_api.py",
)
@click.option(
    "--ble",
    "ble_path",
    type=click.Path(exists=True, path_type=Path),
    required=True,
    help="BLE JSONL (probe/listen) or parse_pklg timeline JSON",
)
@click.option(
    "--window",
    "-w",
    default=5.0,
    show_default=True,
    help="Match events within ±N seconds.",
)
@click.option(
    "-o",
    "--output",
    type=click.Path(path_type=Path),
    default=Path("captures/correlation.json"),
    show_default=True,
)
def main(api_path: Path, ble_path: Path, window: float, output: Path) -> None:
    """Find API requests that occurred near BLE ATT events."""
    api_events = load_jsonl(api_path)
    if ble_path.suffix == ".jsonl":
        ble_events = load_jsonl(ble_path)
    else:
        ble_events = load_timeline(ble_path)

    results = correlate(api_events, ble_events, window_seconds=window)

    output.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "api_source": str(api_path),
        "ble_source": str(ble_path),
        "window_seconds": window,
        "match_count": len(results),
        "matches": results,
    }
    output.write_text(json.dumps(report, indent=2))

    table = Table(title=f"Correlations (±{window}s)")
    table.add_column("API time")
    table.add_column("Path")
    table.add_column("BLE events")

    for row in results[:20]:
        table.add_row(
            str(row.get("api_timestamp", ""))[:19],
            str(row.get("api_path", ""))[:40],
            str(row.get("ble_event_count", 0)),
        )

    console.print(table)
    console.print(f"[green]Wrote {len(results)} match(es) → {output}[/green]")
    if not results:
        console.print(
            "[yellow]No matches. Ensure captures overlap in time and use ISO timestamps.[/yellow]"
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
