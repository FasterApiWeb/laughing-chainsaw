"""Binary parsers for wearable health data (construct-based)."""

from __future__ import annotations

from typing import Any

from construct import Array, Byte, Const, Int16sl, Struct, this

# Oura application framing: tag (1) + length (1) + payload (length)
OuraPacket = Struct(
    "tag" / Byte,
    "length" / Byte,
    "payload" / Bytes(this.length),
)

# Generic 3-axis accelerometer sample (configurable scale applied after parse)
AccelerometerSample = Struct(
    "x" / Int16sl,
    "y" / Int16sl,
    "z" / Int16sl,
)

AccelerometerFrame = Struct(
    "magic" / Const(b"\xAC"),
    "sample_count" / Byte,
    "samples" / Array(this.sample_count, AccelerometerSample),
)

# PPG waveform chunk (LED ADC values, vendor-specific resolution)
PPGSample = Struct("adc" / Int16sl)
PPGFrame = Struct(
    "channel" / Byte,
    "sample_count" / Byte,
    "samples" / Array(this.sample_count, PPGSample),
)

# Skin temperature (centidegrees Celsius, little-endian)
TemperatureReading = Struct(
    "sensor_id" / Byte,
    "centidegrees_c" / Int16sl,
)


def parse_oura_packet(data: bytes) -> dict[str, Any]:
    return OuraPacket.parse(data)


def parse_accelerometer(
    data: bytes,
    *,
    scale: float = 1.0 / 2048.0,
) -> dict[str, Any]:
    parsed = AccelerometerFrame.parse(data)
    for sample in parsed.samples:
        sample.x = round(sample.x * scale, 6)
        sample.y = round(sample.y * scale, 6)
        sample.z = round(sample.z * scale, 6)
    return parsed


def parse_ppg(data: bytes) -> dict[str, Any]:
    return PPGFrame.parse(data)


def parse_temperature(data: bytes) -> dict[str, Any]:
    parsed = TemperatureReading.parse(data)
    parsed.celsius = parsed.centidegrees_c / 100.0
    return parsed


def try_parse_payload(tag: int, payload: bytes) -> dict[str, Any] | None:
    """Best-effort decode by Oura tag; returns None if format unknown."""
    if tag == 0x0D and len(payload) >= 1:
        return {"battery_percent": payload[0]}
    if tag == 0x09 and len(payload) >= 18:
        return {
            "api_version": list(payload[0:3]),
            "firmware_version": list(payload[3:6]),
            "mac": ":".join(f"{b:02x}" for b in reversed(payload[12:18])),
        }
    return None
