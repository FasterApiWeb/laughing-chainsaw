"""Minimal Oura BLE protocol helpers (from open_oura, MIT)."""

from __future__ import annotations

import struct
from typing import Any

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

AUTH_RESULTS = {
    0x00: "success",
    0x01: "authentication_error",
    0x02: "in_factory_reset",
    0x03: "not_original_onboarded_device",
}

CMD_FIRMWARE = bytes.fromhex("0803000000")
CMD_BATTERY = bytes.fromhex("0c00")
CMD_AUTH_NONCE = bytes.fromhex("2f012b")
CMD_SET_NOTIFICATION = bytes.fromhex("1c013f")
CMD_FACTORY_RESET = bytes.fromhex("1a00")

FEATURE_DAYTIME_HR = 0x02
FEATURE_SPO2 = 0x04
FEATURE_MODE_AUTOMATIC = 0x01


def packet(tag: int, payload: bytes = b"") -> bytes:
    if len(payload) > 255:
        raise ValueError("payload too long for one Oura packet")
    return bytes([tag, len(payload)]) + payload


def aes_ecb_encrypt_pkcs7(data: bytes, key: bytes) -> bytes:
    padder = padding.PKCS7(128).padder()
    padded = padder.update(data) + padder.finalize()
    cipher = Cipher(algorithms.AES(key), modes.ECB())
    encryptor = cipher.encryptor()
    return encryptor.update(padded) + encryptor.finalize()


def authenticate_request(key: bytes, nonce: bytes) -> bytes:
    encrypted = aes_ecb_encrypt_pkcs7(nonce, key)
    return packet(0x2F, bytes([0x2D]) + encrypted)


def set_auth_key_request(key: bytes) -> bytes:
    if len(key) != 16:
        raise ValueError("auth key must be 16 bytes")
    return packet(0x24, key)


def set_feature_mode_request(feature: int, mode: int) -> bytes:
    return bytes([0x2F, 0x03, 0x22, feature, mode])


def sync_time_request(unix_secs: int, timezone_half_hours: int = 0) -> bytes:
    payload = struct.pack("<QB", unix_secs, timezone_half_hours & 0xFF)
    return packet(0x12, payload)


def generate_auth_key() -> bytes:
    """Match Oura app key generation (UUID v4 → 16 bytes LE)."""
    import uuid

    u = uuid.uuid4()
    return struct.pack("<QQ", u.int >> 64, u.int & ((1 << 64) - 1))


def parse_packet(data: bytes) -> dict[str, Any]:
    parsed: dict[str, Any] = {"hex": data.hex(), "length": len(data)}
    if len(data) < 2:
        return parsed

    tag = data[0]
    length = data[1]
    payload = data[2:]
    parsed.update({"tag": tag, "length_field": length, "payload_hex": payload.hex()})

    if tag == 0x09 and len(payload) >= 18:
        parsed.update(
            {
                "api_version": ".".join(str(x) for x in payload[0:3]),
                "firmware_version": ".".join(str(x) for x in payload[3:6]),
                "bootloader_version": ".".join(str(x) for x in payload[6:9]),
                "bt_stack_version": ".".join(str(x) for x in payload[9:12]),
                "mac": ":".join(f"{byte:02x}" for byte in reversed(payload[12:18])),
            }
        )
    elif tag == 0x0D and len(payload) >= 1:
        parsed["battery_percent"] = payload[0]
        if len(payload) >= 2:
            parsed["charging_progress"] = payload[1]
    elif tag == 0x1B and len(payload) >= 2:
        parsed["factory_reset_status"] = struct.unpack("<H", payload[:2])[0]
    elif tag == 0x25 and payload:
        parsed["set_auth_key_status"] = payload[0]
    elif tag == 0x2F and payload:
        ext = payload[0]
        parsed["extended_tag"] = ext
        if ext == 0x2C:
            parsed["auth_nonce"] = payload[1:].hex()
        elif ext in (0x2E, 0x2F) and len(payload) >= 2:
            parsed["auth_state"] = payload[1]
            parsed["auth_state_name"] = AUTH_RESULTS.get(payload[1], "unknown")

    return parsed


def describe_packet(data: bytes) -> str:
    parsed = parse_packet(data)
    parts = [f"tag=0x{parsed.get('tag', 0):02x}"]
    for key in (
        "auth_nonce",
        "auth_state_name",
        "battery_percent",
        "firmware_version",
        "factory_reset_status",
        "api_version",
        "mac",
    ):
        if key in parsed:
            parts.append(f"{key}={parsed[key]}")
    return " ".join(parts)


def extract_auth_nonce(data: bytes) -> bytes | None:
    parsed = parse_packet(data)
    nonce_hex = parsed.get("auth_nonce")
    if isinstance(nonce_hex, str) and nonce_hex:
        return bytes.fromhex(nonce_hex)
    return None
