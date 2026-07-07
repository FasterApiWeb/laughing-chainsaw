"""Shared BLE session helpers for Oura tools."""

from __future__ import annotations

import asyncio
from typing import Any, Callable

from bleak import BleakClient
from bleak.backends.device import BLEDevice
from bleak.exc import BleakError

from oura_protocol import (
    CMD_AUTH_NONCE,
    authenticate_request,
    extract_auth_nonce,
    parse_packet,
)

CMD_CHAR = "98ed0002-a541-11e4-b6a0-0002a5d5c51b"
DATA_CHAR = "98ed0003-a541-11e4-b6a0-0002a5d5c51b"


def peer_removed_pairing_help() -> str:
    return (
        "macOS has stale Bluetooth bonding for this ring (CBError 14).\n"
        "The ring was reset or re-paired elsewhere; the Mac still remembers the old bond.\n\n"
        "Fix:\n"
        "  1. System Settings → Bluetooth → find the Oura ring → Forget / Remove\n"
        "     (or hold Option → Bluetooth menu bar icon → Debug → Reset Bluetooth module)\n"
        "  2. Force-quit the Oura iPhone app; put ring on charger near the Mac\n"
        "  3. Re-scan: python scan_oura.py — the CoreBluetooth UUID may change\n"
        "  4. Retry without --address first, or use the new address from the scan table"
    )


def is_peer_removed_error(exc: BaseException) -> bool:
    text = str(exc)
    return "Code=14" in text or "Peer removed pairing" in text


async def transact(
    client: BleakClient,
    queue: asyncio.Queue[bytes],
    request: bytes,
    *,
    wait: float = 2.0,
) -> list[bytes]:
    while not queue.empty():
        queue.get_nowait()
    await client.write_gatt_char(CMD_CHAR, request, response=True)
    responses: list[bytes] = []
    deadline = asyncio.get_event_loop().time() + wait
    while asyncio.get_event_loop().time() < deadline:
        try:
            remaining = deadline - asyncio.get_event_loop().time()
            data = await asyncio.wait_for(queue.get(), timeout=remaining)
            responses.append(data)
        except asyncio.TimeoutError:
            break
    return responses


async def authenticate(
    client: BleakClient,
    queue: asyncio.Queue[bytes],
    key: bytes,
    *,
    log: Callable[[str, bytes | None], Any] | None = None,
) -> bool:
    def _log(msg: str, data: bytes | None = None) -> None:
        if log:
            log(msg, data)

    _log("TX GetAuthNonce")
    nonce_responses = await transact(client, queue, CMD_AUTH_NONCE)
    nonce: bytes | None = None
    for resp in nonce_responses:
        nonce = extract_auth_nonce(resp)
        if nonce:
            _log("RX nonce", resp)
            break

    if not nonce:
        return False

    auth_req = authenticate_request(key, nonce)
    _log("TX Authenticate")
    auth_responses = await transact(client, queue, auth_req)
    for resp in auth_responses:
        parsed = parse_packet(resp)
        state = parsed.get("auth_state_name")
        _log(f"RX auth {state}", resp)
        if state == "success":
            return True
    return False


async def open_session(
    device: BLEDevice,
    *,
    connect_timeout: float,
) -> tuple[BleakClient, asyncio.Queue[bytes]]:
    queue: asyncio.Queue[bytes] = asyncio.Queue()

    def on_notify(_handle: int, data: bytearray) -> None:
        queue.put_nowait(bytes(data))

    client = BleakClient(device, timeout=connect_timeout)
    try:
        await client.connect()
    except BleakError as exc:
        if is_peer_removed_error(exc):
            raise BleakError(f"{exc}\n\n{peer_removed_pairing_help()}") from exc
        raise

    await client.start_notify(DATA_CHAR, on_notify)
    return client, queue


async def close_session(client: BleakClient) -> None:
    try:
        await client.stop_notify(DATA_CHAR)
    except BleakError:
        pass
    if client.is_connected:
        await client.disconnect()
