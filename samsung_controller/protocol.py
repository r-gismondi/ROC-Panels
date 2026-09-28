"""Samsung MDC packet codec.

Get packets always have an empty payload. Set packets are limited to power
and brightness commands used by the wall console.
"""

from __future__ import annotations

HEADER = 0xAA
RESPONSE_COMMAND = 0xFF
ACK = 0x41
NAK = 0x4E

# Commands the probe is allowed to send. Every one is a get: data length 0.
# Set-capable commands are queried the same way; the payload stays empty.
# Commands the wall console may set. Values stay inside the ranges below.
SET_COMMANDS: dict[str, int] = {
    "power": 0x11,
    "backlight": 0x58,
    "picture_brightness": 0x25,
}

GET_COMMANDS: dict[str, int] = {
    "status": 0x00,
    "serial_number": 0x0B,
    "error_status": 0x0D,
    "software_version": 0x0E,
    "model_number": 0x10,
    "power": 0x11,
    "volume": 0x12,
    "mute": 0x13,
    "input_source": 0x14,
    "picture_brightness": 0x25,
    "backlight": 0x58,
    "device_name": 0x67,
    "panel_on_time": 0x83,
    "video_wall": 0x84,
    "model_name": 0x8A,
    "video_wall_mode": 0x5C,
    "video_wall_layout": 0x89,
}

POWER_STATES = {0x00: "off", 0x01: "on", 0x02: "reboot"}
MUTE_STATES = {0x00: "off", 0x01: "on", 0xFF: "unavailable"}
VIDEO_WALL_STATES = {0x00: "off", 0x01: "on"}
VIDEO_WALL_MODES = {0x00: "natural", 0x01: "full"}
LAMP_ERRORS = {0x00: "normal", 0x01: "error"}
TEMP_ERRORS = {0x00: "normal", 0x01: "error"}
SENSOR_ERRORS = {0x00: "none", 0x01: "error", 0x02: "normal"}
SOURCE_ERRORS = {0x00: "normal", 0x01: "error", 0x02: "invalid"}
FAN_ERRORS = {0x00: "normal", 0x01: "error", 0x02: "unsupported"}
MODEL_SPECIES = {
    0x01: "PDP",
    0x02: "LCD",
    0x03: "DLP",
    0x04: "LED",
    0x05: "CRT",
    0x06: "OLED",
}

INPUT_SOURCES = {
    0x00: "none",
    0x04: "s-video",
    0x08: "component",
    0x0C: "av",
    0x0D: "av2",
    0x0E: "scart1",
    0x14: "pc",
    0x18: "dvi",
    0x1E: "bnc",
    0x1F: "dvi-video",
    0x20: "magicinfo",
    0x21: "hdmi1",
    0x22: "hdmi1-pc",
    0x23: "hdmi2",
    0x24: "hdmi2-pc",
    0x25: "displayport1",
    0x26: "displayport2",
    0x27: "displayport3",
    0x30: "rf-tv",
    0x31: "hdmi3",
    0x32: "hdmi3-pc",
    0x33: "hdmi4",
    0x34: "hdmi4-pc",
    0x40: "tv",
    0x50: "plug-in-module",
    0x55: "hdbaset",
    0x56: "ocm",
    0x60: "media-magicinfo-s",
    0x61: "widi-screen-mirroring",
    0x62: "internal-usb",
    0x63: "url-launcher",
    0x64: "iwb",
    0x65: "web-browser",
    0x66: "remote-workspace",
}

PICTURE_ASPECTS = {
    0x00: "video-auto-wide",
    0x01: "video-16:9",
    0x04: "video-zoom",
    0x05: "video-zoom-1",
    0x06: "video-zoom-2",
    0x09: "video-screen-fit",
    0x0B: "video-4:3",
    0x0C: "video-wide-fit",
    0x0D: "video-custom",
    0x0E: "video-smart-view-1",
    0x0F: "video-smart-view-2",
    0x10: "pc-16:9",
    0x18: "pc-4:3",
    0x20: "pc-original",
    0x21: "pc-21:9",
    0x22: "pc-custom",
    0x31: "video-wide-zoom",
    0x32: "video-21:9",
}


class ProtocolError(Exception):
    """A response could not be decoded."""


def build_set_packet(command_name: str, display_id: int, value: int) -> bytes:
    """Build a one-byte set packet for power or brightness."""
    command = SET_COMMANDS.get(command_name)
    if command is None:
        raise ValueError(f"{command_name} cannot be set")
    if not 0 <= display_id <= 0xFE:
        raise ValueError(f"display id {display_id} is outside 0..254")
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{command_name} value must be an integer")
    if command_name == "power":
        if value not in (0, 1):
            raise ValueError("power must be 0 or 1")
    elif not 0 <= value <= 100:
        raise ValueError(f"{command_name} must be from 0 to 100")
    body = bytes([command & 0xFF, display_id & 0xFF, 0x01, value & 0xFF])
    return bytes([HEADER]) + body + bytes([sum(body) & 0xFF])


def build_get_packet(command: int, display_id: int) -> bytes:
    """Build a get packet. The data length byte is always zero."""
    if command not in GET_COMMANDS.values():
        raise ValueError(f"command 0x{command:02X} is not a read query")
    if not 0 <= display_id <= 0xFE:
        raise ValueError(f"display id {display_id} is outside 0..254")
    body = bytes([command & 0xFF, display_id & 0xFF, 0x00])
    packet = bytes([HEADER]) + body + bytes([sum(body) & 0xFF])
    if packet[3] != 0:
        raise RuntimeError("refusing to emit an MDC packet with a payload")
    return packet


def _checksum(packet_without_header_or_sum: bytes) -> int:
    return sum(packet_without_header_or_sum) & 0xFF


def parse_response(buffer: bytes) -> tuple[dict, bytes]:
    """Decode one response packet. Returns the message and leftover bytes."""
    if not buffer:
        raise ProtocolError("empty response")
    start = buffer.find(bytes([HEADER]))
    if start < 0:
        raise ProtocolError(f"no MDC header in {buffer[:16]!r}")
    buffer = buffer[start:]
    if len(buffer) < 5:
        raise ProtocolError("truncated MDC header")
    command = buffer[1]
    display_id = buffer[2]
    length = buffer[3]
    total = 5 + length
    if len(buffer) < total:
        raise ProtocolError(
            f"truncated MDC response: have {len(buffer)} of {total} bytes"
        )
    packet = buffer[:total]
    expected = _checksum(packet[1:-1])
    if packet[-1] != expected:
        raise ProtocolError(
            f"checksum mismatch: got 0x{packet[-1]:02X}, expected 0x{expected:02X}"
        )
    if command != RESPONSE_COMMAND:
        raise ProtocolError(f"unexpected response command 0x{command:02X}")
    if length < 2:
        raise ProtocolError(f"response length {length} is too short")
    payload = packet[4:-1]
    ack = payload[0]
    request_command = payload[1]
    data = payload[2:]
    if ack not in (ACK, NAK):
        raise ProtocolError(f"unexpected ack byte 0x{ack:02X}")
    return {
        "display_id": display_id,
        "ack": ack == ACK,
        "command": request_command,
        "data": data,
        "nak_code": None if ack == ACK else (data[0] if data else None),
        "raw": packet,
    }, buffer[total:]


def _named(table: dict[int, str], value: int) -> str:
    label = table.get(value)
    if label is None:
        return f"unknown-0x{value:02X}"
    return label


def _text(data: bytes) -> str:
    return data.split(b"\x00", 1)[0].decode("ascii", errors="replace").strip()


def describe(command_name: str, data: bytes) -> dict:
    """Turn response data for a known get into labeled fields."""
    if command_name == "status":
        fields = {}
        if len(data) >= 1:
            fields["power"] = _named(POWER_STATES, data[0])
            fields["power_code"] = data[0]
        if len(data) >= 2:
            fields["volume"] = data[1]
        if len(data) >= 3:
            fields["mute"] = _named(MUTE_STATES, data[2])
        if len(data) >= 4:
            fields["input"] = _named(INPUT_SOURCES, data[3])
            fields["input_code"] = data[3]
        if len(data) >= 5:
            fields["picture_aspect"] = _named(PICTURE_ASPECTS, data[4])
        return fields
    if command_name == "power":
        if not data:
            return {}
        return {"power": _named(POWER_STATES, data[0]), "power_code": data[0]}
    if command_name == "input_source":
        if not data:
            return {}
        return {"input": _named(INPUT_SOURCES, data[0]), "input_code": data[0]}
    if command_name == "backlight":
        if not data:
            return {}
        return {"backlight": data[0]}
    if command_name == "picture_brightness":
        if not data:
            return {}
        return {"picture_brightness": data[0]}
    if command_name == "volume":
        if not data:
            return {}
        return {"volume": data[0]}
    if command_name == "mute":
        if not data:
            return {}
        return {"mute": _named(MUTE_STATES, data[0])}
    if command_name == "video_wall":
        if not data:
            return {}
        return {"video_wall": _named(VIDEO_WALL_STATES, data[0])}
    if command_name == "video_wall_mode":
        if not data:
            return {}
        return {"video_wall_mode": _named(VIDEO_WALL_MODES, data[0])}
    if command_name == "video_wall_layout":
        if not data:
            return {}
        rows = (data[0] >> 4) & 0x0F
        columns = data[0] & 0x0F
        fields = {"wall_rows": rows, "wall_columns": columns}
        if len(data) >= 2:
            fields["wall_position"] = data[1]
        return fields
    if command_name in {"model_name", "serial_number", "software_version", "device_name"}:
        return {command_name: _text(data)}
    if command_name == "model_number":
        fields = {}
        if data:
            fields["model_species"] = _named(MODEL_SPECIES, data[0])
        if len(data) >= 2:
            fields["model_code"] = data[1]
        return fields
    if command_name == "panel_on_time":
        ticks = int.from_bytes(data, "big") if data else 0
        return {
            "panel_on_time_ticks": ticks,
            "panel_on_time_hours": round(ticks / 6, 1),
        }
    if command_name == "error_status":
        fields = {}
        names = (
            ("lamp", LAMP_ERRORS),
            ("temperature_sensor", TEMP_ERRORS),
            ("brightness_sensor", SENSOR_ERRORS),
            ("input_signal", SOURCE_ERRORS),
        )
        for index, (name, table) in enumerate(names):
            if len(data) > index:
                fields[name] = _named(table, data[index])
        if len(data) >= 5:
            fields["temperature_c"] = data[4]
        if len(data) >= 6:
            fields["fan"] = _named(FAN_ERRORS, data[5])
        return fields
    return {"raw": data.hex()}
