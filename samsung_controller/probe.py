"""Read-only probe of Samsung MDC panels.

Usage:
    python -m samsung_controller.probe --panels 1

The process never sends a power, backlight, input, or video-wall write.
Every packet is a get with a zero data length.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from samsung_controller.client import query_panel
from samsung_controller.config import PanelNetwork, load_config, parse_panels
from samsung_controller.protocol import GET_COMMANDS

# Order is the report order. status is sent first to learn the display id.
QUERIES = (
    "status",
    "model_name",
    "model_number",
    "serial_number",
    "software_version",
    "device_name",
    "power",
    "input_source",
    "backlight",
    "picture_brightness",
    "video_wall",
    "video_wall_mode",
    "video_wall_layout",
    "panel_on_time",
    "error_status",
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read Samsung display status over MDC. Does not change settings."
    )
    parser.add_argument(
        "--panels",
        required=True,
        help="1-based panel numbers to read, for example 1 or 1,2 or 1-4",
    )
    parser.add_argument(
        "--config",
        default="config/panels.json",
        help="path to panels.json (default: config/panels.json)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=4.0,
        help="TCP connect and response timeout in seconds (default: 4)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print the probe result as JSON",
    )
    args = parser.parse_args(argv)

    if args.timeout <= 0:
        parser.error("--timeout must be positive")

    network = load_config(Path(args.config))
    panels = parse_panels(args.panels)
    _reject_writes()

    reports = [
        _probe_one(network, panel, args.timeout) for panel in panels
    ]
    if args.json:
        json.dump(reports, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        _print_reports(network, reports, args.config)

    if any(item["readings"] for item in reports):
        return 0
    return 2


def _probe_one(network: PanelNetwork, panel: int, timeout: float) -> dict:
    host, port = network.address_for(panel)
    if network.display_id is None:
        display_ids = [0, 1]
        if panel not in display_ids:
            display_ids.append(panel)
    else:
        display_ids = [network.display_id]
    report = query_panel(host, port, QUERIES, display_ids, timeout)
    report["panel"] = panel
    return report


def _print_reports(network: PanelNetwork, reports: list[dict], config_path: str) -> None:
    print("Samsung MDC probe (read-only)")
    print(f"config: {config_path}")
    print(
        "addressing: "
        f"{network.network_prefix}.(host_offset + panel - 1), "
        f"host_offset {network.host_offset}, port {network.port}"
    )
    print("writes: none (power, backlight, input, and wall layout are not sent)")
    for report in reports:
        print()
        print(f"Panel {report['panel']}  {report['host']}:{report['port']}")
        if not report["reachable"]:
            print("  result: unreachable")
            print(f"  error: {report['error']}")
            continue
        print("  result: connected")
        if report["display_id"] is None:
            print(f"  error: {report['error']}")
            continue
        print(f"  display_id: {report['display_id']}")
        if report["error"]:
            print(f"  error: {report['error']}")
        _print_readings(report["readings"])


def _print_readings(readings: dict) -> None:
    status = readings.get("status") or {}
    power = _prefer(readings, "power", "power", status.get("power"))
    source = _prefer(readings, "input_source", "input", status.get("input"))
    _line("model", _value(readings, "model_name", "model_name"))
    species = _value(readings, "model_number", "model_species")
    code = _value(readings, "model_number", "model_code")
    if species is not None or code is not None:
        print(f"  model_number: {species or '?'} code {code if code is not None else '?'}")
    _line("serial", _value(readings, "serial_number", "serial_number"))
    _line("software", _value(readings, "software_version", "software_version"))
    _line("device_name", _value(readings, "device_name", "device_name"))
    _line("power", power)
    if status.get("volume") is not None:
        print(f"  volume: {status['volume']}")
    if status.get("mute") is not None:
        print(f"  mute: {status['mute']}")
    _line("input", source)
    if status.get("picture_aspect") is not None:
        print(f"  picture_aspect: {status['picture_aspect']}")
    _line("backlight", _value(readings, "backlight", "backlight"))
    _line("picture_brightness", _value(readings, "picture_brightness", "picture_brightness"))
    _line("video_wall", _value(readings, "video_wall", "video_wall"))
    _line("video_wall_mode", _value(readings, "video_wall_mode", "video_wall_mode"))
    layout = readings.get("video_wall_layout") or {}
    if layout.get("ack"):
        rows = layout.get("wall_rows")
        columns = layout.get("wall_columns")
        position = layout.get("wall_position")
        print(f"  video_wall_layout: {columns} columns x {rows} rows, position {position}")
    elif layout:
        print(f"  video_wall_layout: {_failure(layout)}")
    on_time = readings.get("panel_on_time") or {}
    if on_time.get("ack"):
        print(f"  panel_on_time_hours: {on_time.get('panel_on_time_hours')}")
    elif on_time:
        print(f"  panel_on_time: {_failure(on_time)}")
    errors = readings.get("error_status") or {}
    if errors.get("ack"):
        parts = [
            f"{name}={errors[name]}"
            for name in (
                "lamp",
                "temperature_sensor",
                "brightness_sensor",
                "input_signal",
                "temperature_c",
                "fan",
            )
            if name in errors
        ]
        print(f"  error_status: {', '.join(parts)}")
    elif errors:
        print(f"  error_status: {_failure(errors)}")


def _prefer(readings: dict, command: str, field: str, fallback: object) -> object:
    reading = readings.get(command) or {}
    if reading.get("ack") and field in reading:
        return reading[field]
    if reading and not reading.get("ack") and fallback is None:
        return _failure(reading)
    return fallback


def _value(readings: dict, command: str, field: str) -> object:
    reading = readings.get(command) or {}
    if reading.get("ack"):
        return reading.get(field)
    if reading:
        return _failure(reading)
    return None


def _failure(reading: dict) -> str:
    return str(reading.get("error") or "no data")


def _line(label: str, value: object) -> None:
    if value is not None:
        print(f"  {label}: {value}")


def _reject_writes() -> None:
    """Fail closed if a query name is not an empty-get command."""
    unknown = [name for name in QUERIES if name not in GET_COMMANDS]
    if unknown:
        raise SystemExit(f"refusing to send non-get commands: {', '.join(unknown)}")


if __name__ == "__main__":
    sys.exit(main())
