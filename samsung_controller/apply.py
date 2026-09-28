"""Set or read power and brightness on the wall displays.

The probe stays read-only. This module is what the center panel calls.
Screen TV1 is panel 1, through TV18.
"""

from __future__ import annotations

import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from samsung_controller.client import PanelError, ReadOnlyMdcClient, _connect_error
from samsung_controller.config import PanelNetwork, load_config

SCREEN_COUNT = 18


def screen_number(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise ValueError("screens are TV1 through TV18")
    text = str(value).strip().upper()
    if text.startswith("TV"):
        text = text[2:]
    if not text.isdigit():
        raise ValueError("screens are TV1 through TV18")
    number = int(text)
    if not 1 <= number <= SCREEN_COUNT:
        raise ValueError("screens are TV1 through TV18")
    return number


def run(request: dict, network: PanelNetwork | None = None, timeout: float = 1.0) -> dict:
    if not isinstance(request, dict):
        raise ValueError("request must be an object")
    action = request.get("action")
    if action not in ("read", "set"):
        raise ValueError("action must be read or set")
    raw_screens = request.get("screens")
    if not isinstance(raw_screens, list) or not raw_screens:
        raise ValueError("pick at least one screen")
    screens: list[int] = []
    seen: set[int] = set()
    for item in raw_screens:
        number = screen_number(item)
        if number not in seen:
            seen.add(number)
            screens.append(number)
    power = request.get("power", None)
    brightness = request.get("brightness", None)
    if action == "set":
        if power is None and brightness is None:
            raise ValueError("pick power or brightness")
        if power is not None and not isinstance(power, bool):
            raise ValueError("power must be true or false")
        if brightness is not None and (
            isinstance(brightness, bool) or not isinstance(brightness, int) or not 0 <= brightness <= 100
        ):
            raise ValueError("brightness must be from 0 to 100")
    if network is None:
        network = load_config(Path("config/panels.json"))
    workers = min(8, len(screens))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(
            pool.map(
                lambda screen: _one(network, screen, timeout, action, power, brightness),
                screens,
            )
        )
    return {"results": results}


def _display_ids(network: PanelNetwork, panel: int) -> list[int]:
    if network.display_id is not None:
        return [network.display_id]
    # These panels answer on their own number. Id 0 and id 1 stay silent, so
    # trying them first waits out the socket timeout before the command is sent.
    display_ids: list[int] = []
    for display_id in (panel, 0, 1):
        if display_id not in display_ids:
            display_ids.append(display_id)
    return display_ids


def _one(
    network: PanelNetwork,
    panel: int,
    timeout: float,
    action: str,
    power: bool | None,
    brightness: int | None,
) -> dict:
    screen = f"TV{panel}"
    host, port = network.address_for(panel)
    client = ReadOnlyMdcClient(host, port, timeout=timeout)
    try:
        client.connect()
    except OSError as exc:
        return {"screen": screen, "ok": False, "error": _connect_error(exc)}
    try:
        return _command(client, screen, _display_ids(network, panel), action, power, brightness)
    finally:
        client.close()


def _command(
    client: ReadOnlyMdcClient,
    screen: str,
    display_ids: list[int],
    action: str,
    power: bool | None,
    brightness: int | None,
) -> dict:
    last_error = "The display did not answer."
    for index, display_id in enumerate(display_ids):
        try:
            if action == "read":
                result = _read(client, screen, display_id)
            else:
                result = _write(client, screen, display_id, power, brightness)
        except PanelError as exc:
            last_error = str(exc) or last_error
            if index + 1 == len(display_ids):
                break
            try:
                client.connect()
            except OSError as connect_exc:
                return {"screen": screen, "ok": False, "error": _connect_error(connect_exc)}
            continue
        return result
    return {"screen": screen, "ok": False, "error": last_error}


def _exchange(client: ReadOnlyMdcClient, kind: str, name: str, display_id: int, value: int | None = None) -> dict:
    def once() -> dict:
        if kind == "get":
            return client.get(name, display_id)
        if value is None:
            raise PanelError("missing value")
        return client.set(name, display_id, value)

    try:
        return once()
    except PanelError as exc:
        # A silent id should fail once. Retry only when the panel closes the socket.
        if "timed out" in str(exc).lower():
            raise
        client.connect()
        return once()


def _read(client: ReadOnlyMdcClient, screen: str, display_id: int) -> dict:
    power_message = _exchange(client, "get", "power", display_id)
    if not power_message["ack"]:
        return {"screen": screen, "ok": False, "error": _nak(power_message)}
    brightness, error = _read_brightness(client, display_id)
    if error:
        return {"screen": screen, "ok": False, "error": error}
    state = power_message["fields"].get("power")
    return {
        "screen": screen,
        "ok": True,
        "power": state == "on",
        "brightness": brightness,
    }


def _read_brightness(client: ReadOnlyMdcClient, display_id: int) -> tuple[int | None, str | None]:
    backlight = _exchange(client, "get", "backlight", display_id)
    if backlight["ack"] and "backlight" in backlight["fields"]:
        return int(backlight["fields"]["backlight"]), None
    picture = _exchange(client, "get", "picture_brightness", display_id)
    if picture["ack"] and "picture_brightness" in picture["fields"]:
        return int(picture["fields"]["picture_brightness"]), None
    return None, _nak(backlight)


def _write(
    client: ReadOnlyMdcClient,
    screen: str,
    display_id: int,
    power: bool | None,
    brightness: int | None,
) -> dict:
    result: dict = {"screen": screen, "ok": True}
    if power is not None:
        message = _exchange(client, "set", "power", display_id, 1 if power else 0)
        if not message["ack"]:
            return {"screen": screen, "ok": False, "error": _nak(message)}
        result["power"] = power
    if brightness is not None:
        message = _exchange(client, "set", "backlight", display_id, brightness)
        if not message["ack"]:
            message = _exchange(client, "set", "picture_brightness", display_id, brightness)
        if not message["ack"]:
            return {"screen": screen, "ok": False, "error": _nak(message)}
        result["brightness"] = brightness
    return result


def _nak(message: dict) -> str:
    code = message.get("nak_code")
    if code is None:
        return "The display did not accept that command."
    return f"The display refused the command ({code})."


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if len(arguments) != 1:
        print(json.dumps({"error": "missing request"}))
        return 1
    try:
        request = json.loads(arguments[0])
        payload = run(request)
    except ValueError as exc:
        print(json.dumps({"error": str(exc)}))
        return 1
    except OSError as exc:
        print(json.dumps({"error": str(exc) or "The displays could not be reached."}))
        return 1
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
