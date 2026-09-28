"""Power and brightness sets reach the selected screens and nowhere else."""

from __future__ import annotations

import socket
import threading
import unittest

from samsung_controller.apply import main, run
from samsung_controller.config import PanelNetwork
from samsung_controller.protocol import HEADER, build_get_packet, build_set_packet


def _packet(command: int, display_id: int, data: bytes, ack: bool = True) -> bytes:
    payload = bytes([0x41 if ack else 0x4E, command]) + data
    body = bytes([0xFF, display_id, len(payload)]) + payload
    return bytes([HEADER]) + body + bytes([sum(body) & 0xFF])


class SetPanel(threading.Thread):
    def __init__(self) -> None:
        super().__init__(daemon=True)
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server.bind(("127.0.0.1", 0))
        self.server.listen(8)
        self.port = self.server.getsockname()[1]
        self.packets: list[bytes] = []
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
                buffer = b""
                while not self._halt.is_set():
                    try:
                        chunk = conn.recv(128)
                    except TimeoutError:
                        break
                    if not chunk:
                        break
                    buffer += chunk
                    while len(buffer) >= 5 and buffer[0] == HEADER:
                        length = buffer[3]
                        total = 5 + length
                        if len(buffer) < total:
                            break
                        packet = buffer[:total]
                        buffer = buffer[total:]
                        self.packets.append(packet)
                        command = packet[1]
                        display_id = packet[2]
                        if display_id != 0:
                            continue
                        if length == 0:
                            data = {0x00: bytes([0x01]), 0x11: bytes([0x01]), 0x58: bytes([70])}.get(command, b"")
                            conn.sendall(_packet(command, display_id, data))
                        elif length == 1 and command in (0x11, 0x58):
                            conn.sendall(_packet(command, display_id, packet[4:5]))
                        else:
                            conn.sendall(_packet(command, display_id, bytes([0x01]), ack=False))

    def close(self) -> None:
        self._halt.set()
        self.server.close()


class DisplayApplyTest(unittest.TestCase):
    def test_set_packets_are_one_byte(self) -> None:
        power_on = build_set_packet("power", 0, 1)
        self.assertEqual(power_on, bytes([0xAA, 0x11, 0x00, 0x01, 0x01, 0x13]))
        backlight = build_set_packet("backlight", 0, 50)
        self.assertEqual(backlight, bytes([0xAA, 0x58, 0x00, 0x01, 0x32, 0x8B]))
        self.assertEqual(build_get_packet(0x11, 0)[3], 0)
        with self.assertRaises(ValueError):
            build_set_packet("input_source", 0, 1)
        with self.assertRaises(ValueError):
            build_set_packet("power", 0, 2)
        with self.assertRaises(ValueError):
            build_set_packet("backlight", 0, 101)

    def test_set_reaches_only_the_selected_screen(self) -> None:
        panel = SetPanel()
        panel.start()
        network = PanelNetwork("127.0.0", 0, panel.port, display_id=0)
        try:
            result = run(
                {"action": "set", "screens": ["TV1", 1], "power": True, "brightness": 40},
                network,
                timeout=2,
            )
            self.assertTrue(result["results"][0]["ok"])
            self.assertEqual(result["results"][0]["screen"], "TV1")
            sets = [packet for packet in panel.packets if packet[3] == 1]
            self.assertEqual([(packet[1], packet[4]) for packet in sets], [(0x11, 1), (0x58, 40)])
            self.assertTrue(all(packet[2] == 0 for packet in panel.packets))
        finally:
            panel.close()
            panel.join(timeout=2)

    def test_read_reports_power_and_backlight(self) -> None:
        panel = SetPanel()
        panel.start()
        network = PanelNetwork("127.0.0", 0, panel.port, display_id=0)
        try:
            result = run({"action": "read", "screens": [1]}, network, timeout=2)
            row = result["results"][0]
            self.assertTrue(row["ok"])
            self.assertTrue(row["power"])
            self.assertEqual(row["brightness"], 70)
            self.assertTrue(all(packet[3] == 0 for packet in panel.packets))
        finally:
            panel.close()
            panel.join(timeout=2)

    def test_cli_rejects_a_screen_outside_the_wall(self) -> None:
        code = main(['{"action":"read","screens":["TV19"]}'])
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
