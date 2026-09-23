"""The probe may only emit empty MDC get packets."""

from __future__ import annotations

import json
import socket
import threading
import unittest
from pathlib import Path

from samsung_controller.config import load_config
from samsung_controller.probe import QUERIES, main
from samsung_controller.protocol import GET_COMMANDS, HEADER, build_get_packet


def _packet(command: int, display_id: int, data: bytes, ack: bool = True) -> bytes:
    payload = bytes([0x41 if ack else 0x4E, command]) + data
    body = bytes([0xFF, display_id, len(payload)]) + payload
    return bytes([HEADER]) + body + bytes([sum(body) & 0xFF])


class FakePanel(threading.Thread):
    def __init__(self) -> None:
        super().__init__(daemon=True)
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("127.0.0.1", 0))
        self.server.listen(1)
        self.port = self.server.getsockname()[1]
        self.packets: list[bytes] = []
        self.violations: list[str] = []
        self._halt = threading.Event()

    def run(self) -> None:
        self.server.settimeout(0.5)
        while not self._halt.is_set():
            try:
                conn, _addr = self.server.accept()
            except TimeoutError:
                continue
            except OSError:
                return
            with conn:
                conn.settimeout(1.0)
                self._handle(conn)

    def _handle(self, conn: socket.socket) -> None:
        buffer = b""
        while not self._halt.is_set():
            try:
                chunk = conn.recv(128)
            except TimeoutError:
                return
            if not chunk:
                return
            buffer += chunk
            while len(buffer) >= 5 and buffer[0] == HEADER:
                length = buffer[3]
                total = 5 + length
                if len(buffer) < total:
                    break
                packet = buffer[:total]
                buffer = buffer[total:]
                self.packets.append(packet)
                if length != 0:
                    self.violations.append(f"payload length {length}: {packet.hex()}")
                    continue
                command = packet[1]
                display_id = packet[2]
                if command not in GET_COMMANDS.values():
                    self.violations.append(f"command 0x{command:02X}")
                    continue
                conn.sendall(self._reply(command, display_id))

    def _reply(self, command: int, display_id: int) -> bytes:
        if display_id != 0:
            return b""
        replies = {
            0x00: bytes([0x01, 15, 0x00, 0x21, 0x10, 0x00, 0x00]),
            0x11: bytes([0x01]),
            0x14: bytes([0x21]),
            0x58: bytes([70]),
            0x25: bytes([40]),
            0x84: bytes([0x01]),
            0x5C: bytes([0x01]),
            0x89: bytes([0x32, 0x01]),
            0x8A: b"LH55QMNEBGC",
            0x0B: b"ZYM12345",
            0x0E: b"1000.4",
            0x10: bytes([0x02, 0x55]),
            0x67: b"Lobby-1",
            0x83: (120).to_bytes(2, "big"),
            0x0D: bytes([0x00, 0x00, 0x02, 0x00, 36, 0x00]),
        }
        data = replies.get(command)
        if data is None:
            return _packet(command, display_id, bytes([0x01]), ack=False)
        return _packet(command, display_id, data)

    def close(self) -> None:
        self._halt.set()
        self.server.close()


class ReadOnlyProbeTest(unittest.TestCase):
    def test_user_config_targets_panel_one(self) -> None:
        network = load_config(Path("config/panels.json"))
        self.assertEqual(network.network_prefix, "192.168.0")
        self.assertEqual(network.host_offset, 1)
        self.assertEqual(network.port, 1515)
        self.assertEqual(network.address_for(1), ("192.168.0.2", 1515))
        self.assertEqual(network.address_for(2), ("192.168.0.3", 1515))

    def test_get_packets_have_empty_payload(self) -> None:
        for name, command in GET_COMMANDS.items():
            packet = build_get_packet(command, 0)
            self.assertEqual(packet[3], 0, name)
            self.assertEqual(len(packet), 5, name)
        with self.assertRaises(ValueError):
            build_get_packet(0xB0, 0)

    def test_probe_does_not_write_panel_state(self) -> None:
        panel = FakePanel()
        panel.start()
        config_path = Path("config") / "panels.test.json"
        try:
            config_path.write_text(
                json.dumps(
                    {
                        "network_prefix": "127.0.0",
                        "host_offset": 0,
                        "port": panel.port,
                    }
                ),
                encoding="utf-8",
            )
            code = main(["--panels", "1", "--config", str(config_path), "--timeout", "2"])
            self.assertEqual(code, 0)
            self.assertEqual(panel.violations, [])
            self.assertTrue(panel.packets)
            commands = [packet[1] for packet in panel.packets]
            self.assertTrue(all(packet[3] == 0 for packet in panel.packets))
            for name in QUERIES:
                self.assertIn(GET_COMMANDS[name], commands)
            # Sensitive controls were queried, never written.
            for command in (0x11, 0x58, 0x14, 0x84, 0x5C, 0x89):
                payloads = [packet for packet in panel.packets if packet[1] == command]
                self.assertTrue(payloads)
                self.assertTrue(all(packet[3] == 0 for packet in payloads))
        finally:
            config_path.unlink(missing_ok=True)
            panel.close()
            panel.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
