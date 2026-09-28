"""TCP client that sends Samsung MDC get requests and nothing else."""

from __future__ import annotations

import socket
from collections.abc import Iterable

from samsung_controller.protocol import (
    GET_COMMANDS,
    ProtocolError,
    build_get_packet,
    build_set_packet,
    describe,
    parse_response,
)

TLS_BANNER = b"MDCSTART<<TLS>>"


class PanelError(Exception):
    """The panel could not be queried."""


class ReadOnlyMdcClient:
    """One TCP session to a single panel.

    ``get`` builds packets with :func:`build_get_packet`, which refuses any
    command outside the get allowlist and always sets the data length to 0.
    """

    def __init__(self, host: str, port: int, timeout: float = 4.0) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self._socket: socket.socket | None = None
        self._buffer = b""

    def connect(self) -> None:
        self.close()
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.settimeout(self.timeout)
        try:
            sock.connect((self.host, self.port))
        except OSError:
            sock.close()
            raise
        self._socket = sock
        self._buffer = b""

    def close(self) -> None:
        if self._socket is not None:
            try:
                self._socket.close()
            finally:
                self._socket = None
                self._buffer = b""

    def __enter__(self) -> ReadOnlyMdcClient:
        self.connect()
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def get(self, command_name: str, display_id: int) -> dict:
        if command_name not in GET_COMMANDS:
            raise ValueError(f"{command_name} is not a read query")
        packet = build_get_packet(GET_COMMANDS[command_name], display_id)
        if packet[3] != 0:
            raise RuntimeError("refusing to send a non-empty MDC payload")
        sock = self._socket
        if sock is None:
            raise PanelError("not connected")
        try:
            sock.sendall(packet)
            message = self._read_message()
        except (TimeoutError, OSError) as exc:
            raise PanelError(str(exc) or exc.__class__.__name__) from exc
        message["request"] = command_name
        if message["ack"]:
            message["fields"] = describe(command_name, message["data"])
        else:
            message["fields"] = {}
        return message

    def set(self, command_name: str, display_id: int, value: int) -> dict:
        packet = build_set_packet(command_name, display_id, value)
        if packet[3] != 1:
            raise RuntimeError("refusing to send an unexpected MDC payload")
        sock = self._socket
        if sock is None:
            raise PanelError("not connected")
        try:
            sock.sendall(packet)
            message = self._read_message()
        except (TimeoutError, OSError) as exc:
            raise PanelError(str(exc) or exc.__class__.__name__) from exc
        message["request"] = command_name
        if message["ack"]:
            message["fields"] = describe(command_name, message["data"])
        else:
            message["fields"] = {}
        return message

    def _read_message(self) -> dict:
        while True:
            if TLS_BANNER in self._buffer or self._buffer.startswith(b"MDCSTART"):
                raise PanelError(
                    "panel asked for an MDC TLS pin; probe stops without authenticating"
                )
            if len(self._buffer) >= 5 and self._buffer[0] == 0xAA:
                length = self._buffer[3]
                if length > 240:
                    raise PanelError(f"refusing oversized MDC length {length}")
                if len(self._buffer) >= 5 + length:
                    try:
                        message, leftover = parse_response(self._buffer)
                    except ProtocolError as exc:
                        raise PanelError(str(exc)) from exc
                    self._buffer = leftover
                    return message
            chunk = self._recv()
            if chunk is None:
                if self._buffer:
                    raise PanelError(f"incomplete response: {self._buffer.hex()}")
                raise PanelError("no response")
            self._buffer += chunk

    def _recv(self) -> bytes | None:
        sock = self._socket
        assert sock is not None
        try:
            chunk = sock.recv(256)
        except TimeoutError as exc:
            raise PanelError("timed out") from exc
        if not chunk:
            return None
        return chunk


def query_panel(
    host: str,
    port: int,
    queries: Iterable[str],
    display_ids: Iterable[int],
    timeout: float,
) -> dict:
    """Connect and run each get. The first id that answers is reused."""
    result: dict = {
        "host": host,
        "port": port,
        "reachable": False,
        "display_id": None,
        "error": None,
        "readings": {},
    }
    client = ReadOnlyMdcClient(host, port, timeout=timeout)
    try:
        client.connect()
    except OSError as exc:
        result["error"] = _connect_error(exc)
        return result

    result["reachable"] = True
    try:
        found = _discover_id(client, list(display_ids))
        if found is None:
            result["error"] = "connected, but no display id answered a status get"
            return result
        chosen, status = found
        result["display_id"] = chosen
        result["readings"]["status"] = _reading(status)
        for name in queries:
            if name == "status":
                continue
            result["readings"][name] = _query_one(client, name, chosen)
    except PanelError as exc:
        result["error"] = str(exc)
    finally:
        client.close()
    return result


def _query_one(client: ReadOnlyMdcClient, name: str, display_id: int) -> dict:
    try:
        message = client.get(name, display_id)
    except PanelError as exc:
        # Some panels close the socket after each command. Reconnect and
        # repeat the same empty get once.
        try:
            client.connect()
            message = client.get(name, display_id)
        except (OSError, PanelError) as retry_exc:
            return {"ack": False, "error": str(retry_exc) or str(exc)}
    return _reading(message)


def _reading(message: dict) -> dict:
    if message["ack"]:
        return {"ack": True, **message["fields"]}
    code = message["nak_code"]
    return {
        "ack": False,
        "nak_code": code,
        "error": f"NAK {code}" if code is not None else "NAK",
    }


def _discover_id(
    client: ReadOnlyMdcClient, display_ids: list[int]
) -> tuple[int, dict] | None:
    last_error: PanelError | None = None
    for display_id in display_ids:
        try:
            message = client.get("status", display_id)
        except PanelError as exc:
            last_error = exc
            if "TLS" in str(exc):
                raise
            try:
                client.connect()
            except OSError as connect_exc:
                raise PanelError(_connect_error(connect_exc)) from connect_exc
            continue
        if message["ack"] or message["nak_code"] is not None:
            return display_id, message
    if last_error and "timed out" not in str(last_error).lower() and "no response" not in str(last_error):
        raise last_error
    return None


def _connect_error(exc: OSError) -> str:
    text = str(exc).strip() or exc.__class__.__name__
    return f"connect failed: {text}"
