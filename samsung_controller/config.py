"""Panel addressing from config/panels.json."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class PanelNetwork:
    network_prefix: str
    host_offset: int
    port: int
    display_id: int | None = None

    def address_for(self, panel: int) -> tuple[str, int]:
        if panel < 1:
            raise ValueError(f"panel numbers start at 1, got {panel}")
        last_octet = self.host_offset + panel
        if not 1 <= last_octet <= 254:
            raise ValueError(
                f"panel {panel} would use host octet {last_octet}; "
                "valid octets are 1..254"
            )
        return f"{self.network_prefix}.{last_octet}", self.port


def load_config(path: Path) -> PanelNetwork:
    try:
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError as exc:
        raise SystemExit(f"config not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(raw, dict):
        raise SystemExit(f"{path} must be a JSON object")

    missing = [key for key in ("network_prefix", "host_offset", "port") if key not in raw]
    if missing:
        raise SystemExit(f"{path} is missing {', '.join(missing)}")

    prefix = raw["network_prefix"]
    if not isinstance(prefix, str) or not _valid_prefix(prefix):
        raise SystemExit(
            "network_prefix must be the first three IPv4 octets, such as 192.168.0"
        )

    offset = raw["host_offset"]
    port = raw["port"]
    if not isinstance(offset, int) or isinstance(offset, bool) or not 0 <= offset <= 254:
        raise SystemExit("host_offset must be an integer from 0 to 254")
    if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
        raise SystemExit("port must be an integer from 1 to 65535")

    display_id = raw.get("display_id")
    if display_id is not None and (
        not isinstance(display_id, int)
        or isinstance(display_id, bool)
        or not 0 <= display_id <= 0xFE
    ):
        raise SystemExit("display_id must be an integer from 0 to 254")

    return PanelNetwork(prefix, offset, port, display_id)


def parse_panels(text: str) -> list[int]:
    """Parse '1', '1,3', or '1-3' into 1-based panel numbers."""
    panels: list[int] = []
    for part in text.split(","):
        piece = part.strip()
        if not piece:
            raise SystemExit("empty panel selector")
        if "-" in piece:
            bounds = piece.split("-")
            if len(bounds) != 2:
                raise SystemExit(f"invalid panel range: {piece}")
            start, end = (_panel_number(bounds[0]), _panel_number(bounds[1]))
            if end < start:
                raise SystemExit(f"invalid panel range: {piece}")
            if end - start > 63:
                raise SystemExit("a single probe can cover at most 64 panels")
            panels.extend(range(start, end + 1))
        else:
            panels.append(_panel_number(piece))
    # Preserve order, drop duplicates.
    seen: set[int] = set()
    unique: list[int] = []
    for panel in panels:
        if panel not in seen:
            seen.add(panel)
            unique.append(panel)
    return unique


def _panel_number(text: str) -> int:
    try:
        value = int(text.strip())
    except ValueError as exc:
        raise SystemExit(f"invalid panel number: {text}") from exc
    if value < 1:
        raise SystemExit(f"panel numbers start at 1, got {value}")
    return value


def _valid_prefix(prefix: str) -> bool:
    parts = prefix.split(".")
    if len(parts) != 3:
        return False
    for part in parts:
        if not part.isdigit():
            return False
        number = int(part)
        if number > 255 or (part != "0" and part.startswith("0")):
            return False
    return True
