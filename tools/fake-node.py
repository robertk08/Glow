#!/usr/bin/env python3
"""A stand-in for the ESP32 node, for working on the app without hardware.

Speaks the Glow protocol (docs/PROTOCOL.md) over a WebSocket and draws the
universe in the terminal, so you can see exactly what the app is sending.

No dependencies on purpose: this has to still run in two years without a
virtualenv, so the WebSocket framing is done by hand rather than pulled in.

    python3 tools/fake-node.py [--port 8080]

Then point the app at <your Mac's IP>:8080 in Settings, or 127.0.0.1:8080 from
the simulator.
"""

import argparse
import base64
import hashlib
import json
import socket
import struct
import sys
import threading
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
FW_VERSION = "fake-1.0"
START = time.time()

universe = bytearray(512)
state = {"blackout": False, "hz": 40, "frames": 0, "bytes": 0}
setup = {"provisioned": True, "ssid": None, "scan_delay": 3.0}
lock = threading.Lock()

# Pretend neighbours, so the network list has something in it to pick from.
FAKE_NETWORKS = [
    {"ssid": "Krause", "rssi": -44, "secure": True, "channel": 6},
    {"ssid": "Krause 5G", "rssi": -58, "secure": True, "channel": 44},
    {"ssid": "FRITZ!Box 7530 GH", "rssi": -67, "secure": True, "channel": 11},
    {"ssid": "Gastzugang", "rssi": -71, "secure": False, "channel": 1},
    {"ssid": "o2-WLAN94", "rssi": -83, "secure": True, "channel": 3},
]


# ---------------------------------------------------------------- framing --

def handshake(conn, request):
    key = None
    for line in request.split("\r\n"):
        if line.lower().startswith("sec-websocket-key:"):
            key = line.split(":", 1)[1].strip()
        elif line.lower().startswith("sec-websocket-protocol:"):
            # The real node has no subprotocol and its library echoes back
            # "arduino", which a strict client then rejects. Catching it here
            # is the difference between a five-minute fix and an afternoon.
            print(f"  WARNING: client offered a subprotocol ({line.split(':', 1)[1].strip()}).")
            print("  The node does not support one. Do not set it.")
    if key is None:
        conn.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
        return False
    accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    conn.sendall(
        (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        ).encode()
    )
    return True


def recv_exact(conn, count):
    buffer = b""
    while len(buffer) < count:
        chunk = conn.recv(count - len(buffer))
        if not chunk:
            return None
        buffer += chunk
    return buffer


def read_frame(conn):
    """Returns (opcode, payload) or None when the peer goes away."""
    header = recv_exact(conn, 2)
    if not header:
        return None
    opcode = header[0] & 0x0F
    masked = header[1] & 0x80
    length = header[1] & 0x7F

    if length == 126:
        length = struct.unpack(">H", recv_exact(conn, 2))[0]
    elif length == 127:
        length = struct.unpack(">Q", recv_exact(conn, 8))[0]

    mask = recv_exact(conn, 4) if masked else None
    payload = recv_exact(conn, length) if length else b""
    if payload is None:
        return None
    if mask:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return opcode, payload


def write_frame(conn, opcode, payload):
    header = bytearray([0x80 | opcode])
    length = len(payload)
    if length < 126:
        header.append(length)
    elif length < (1 << 16):
        header.append(126)
        header += struct.pack(">H", length)
    else:
        header.append(127)
        header += struct.pack(">Q", length)
    conn.sendall(bytes(header) + payload)


def send_json(conn, payload):
    write_frame(conn, 0x1, json.dumps(payload).encode())


# --------------------------------------------------------------- protocol --

def status():
    return {
        "t": "status",
        "fw": FW_VERSION,
        "id": "fake-node",
        "name": "Fake Glow node",
        "hz": state["hz"],
        "blackout": state["blackout"],
        "uptime": int(time.time() - START),
    }


def handle_binary(conn, payload):
    if len(payload) < 6 or payload[0] != 0x01:
        send_json(conn, {"t": "error", "code": "badframe", "message": "not a DMX frame"})
        return
    start = payload[2] | (payload[3] << 8)
    length = payload[4] | (payload[5] << 8)
    values = payload[6:]

    if start < 1 or length != len(values) or start + length - 1 > 512:
        send_json(
            conn,
            {"t": "error", "code": "range", "message": f"start={start} len={length}"},
        )
        return

    with lock:
        universe[start - 1 : start - 1 + length] = values
        state["frames"] += 1
        state["bytes"] += len(payload)


def handle_text(conn, payload):
    try:
        message = json.loads(payload)
    except ValueError:
        send_json(conn, {"t": "error", "code": "json", "message": "unparseable"})
        return

    kind = message.get("t")
    if kind == "hello":
        print(f"  hello from {message.get('client')} v{message.get('version')}")
        send_json(conn, status())
    elif kind == "ping":
        send_json(conn, {"t": "pong", "seq": message.get("seq", 0)})
    elif kind == "blackout":
        state["blackout"] = bool(message.get("on"))
        send_json(conn, status())
    elif kind == "refresh":
        state["hz"] = int(message.get("hz", 40))
        send_json(conn, status())
    elif kind == "identify":
        print("  identify")
        send_json(conn, status())
    else:
        send_json(conn, {"t": "error", "code": "unknown", "message": str(kind)})


# ------------------------------------------------------------------- setup --

def http_reply(conn, payload, status="200 OK"):
    body = json.dumps(payload).encode()
    conn.sendall(
        (
            f"HTTP/1.1 {status}\r\n"
            "Content-Type: application/json\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n\r\n"
        ).encode()
        + body
    )


def handle_http(conn, request):
    """The /api/* setup surface from docs/PROTOCOL.md."""
    line = request.split("\r\n", 1)[0]
    try:
        method, path, _ = line.split(" ")
    except ValueError:
        http_reply(conn, {"ok": False, "error": "bad request"}, "400 Bad Request")
        return

    body = {}
    if "\r\n\r\n" in request:
        raw = request.split("\r\n\r\n", 1)[1].strip()
        if raw:
            try:
                body = json.loads(raw)
            except ValueError:
                pass

    if path == "/api/info":
        http_reply(conn, {
            "fw": FW_VERSION,
            "id": "aabbccddeeff",
            "name": "Fake Glow node",
            "state": "provisioned" if setup["provisioned"] else "unprovisioned",
        })
        print(f"  GET /api/info -> {'provisioned' if setup['provisioned'] else 'unprovisioned'}")

    elif path == "/api/scan":
        # A real scan blocks for seconds. Reproducing that is the point: it is
        # what the app's progress state exists for.
        print(f"  GET /api/scan (taking {setup['scan_delay']}s, as real hardware does)")
        time.sleep(setup["scan_delay"])
        http_reply(conn, {"networks": FAKE_NETWORKS})

    elif path == "/api/provision" and method == "POST":
        ssid = body.get("ssid", "")
        if not ssid:
            http_reply(conn, {"ok": False, "error": "no network given"})
            return
        setup["provisioned"] = True
        setup["ssid"] = ssid
        # Never print the password. The real node does not log it either.
        print(f"  POST /api/provision -> joining {ssid!r}")
        http_reply(conn, {"ok": True})

    elif path == "/api/forget" and method == "POST":
        setup["provisioned"] = False
        setup["ssid"] = None
        print("  POST /api/forget -> back to setup")
        http_reply(conn, {"ok": True})

    else:
        http_reply(conn, {"ok": False, "error": "no such endpoint"}, "404 Not Found")


def serve(conn, address):
    print(f"\nconnected: {address[0]}")
    try:
        request = conn.recv(4096).decode(errors="replace")

        # Plain HTTP unless it is asking to become a WebSocket.
        if "upgrade: websocket" not in request.lower():
            handle_http(conn, request)
            return

        if not handshake(conn, request):
            return
        while True:
            frame = read_frame(conn)
            if frame is None:
                break
            opcode, payload = frame
            if opcode == 0x8:
                break
            elif opcode == 0x2:
                handle_binary(conn, payload)
            elif opcode == 0x1:
                handle_text(conn, payload)
            elif opcode == 0x9:
                write_frame(conn, 0xA, payload)
    except OSError:
        pass
    finally:
        conn.close()
        print(f"disconnected: {address[0]}")


# ------------------------------------------------------------------- view --

def render():
    """Redraws the first 64 channels plus a summary, a few times a second."""
    while True:
        time.sleep(0.4)
        with lock:
            values = bytes(universe)
            frames, sent = state["frames"], state["bytes"]
        active = sum(1 for v in values if v)
        rows = []
        for base in range(0, 64, 16):
            cells = " ".join(f"{values[base + i]:3d}" for i in range(16))
            rows.append(f"  {base + 1:3d} | {cells}")
        blackout = "  BLACKOUT" if state["blackout"] else ""
        joined = f"  network {setup['ssid']}" if setup["ssid"] else "  UNPROVISIONED"
        sys.stdout.write("\033[H\033[J")
        sys.stdout.write(
            f"Glow fake node — {state['hz']} Hz{blackout}{joined if not setup['provisioned'] or setup['ssid'] else ''}\n"
            f"frames {frames}   bytes {sent}   active channels {active}\n\n"
            + "\n".join(rows)
            + "\n\nCtrl-C to stop.\n"
        )
        sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument(
        "--unprovisioned",
        action="store_true",
        help="start as a node that has never been given a network, to exercise setup",
    )
    parser.add_argument("--scan-delay", type=float, default=3.0)
    args = parser.parse_args()

    setup["provisioned"] = not args.unprovisioned
    setup["scan_delay"] = args.scan_delay

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", args.port))
    server.listen(4)

    addresses = socket.gethostbyname_ex(socket.gethostname())[2]
    print(f"listening on port {args.port}")
    for address in addresses:
        print(f"  app setting: {address}:{args.port}")
    print(f"  simulator:   127.0.0.1:{args.port}")

    threading.Thread(target=render, daemon=True).start()

    try:
        while True:
            conn, address = server.accept()
            threading.Thread(target=serve, args=(conn, address), daemon=True).start()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
