#!/usr/bin/env python3
"""Look at and poke a Flipper One's panel through flipctl's browser view.

  panel.py [--host H:P] shot out.png [--scale N]   save the 256x144 panel as an amber PNG
  panel.py [--host H:P] press KEY [KEY...]         press and release device keys
        keys: up down left right ok back esc view power edit run appsw ptt

--host defaults to localhost:8899 (the run.sh VM).
"""
import json, struct, sys, time, urllib.request, zlib

W, H = 256, 144
AMBER = (0xFF, 0x82, 0x00)


def grab(host, timeout=8.0):
    """Read the stream until a full frame has been seen; return W*H grey bytes."""
    panel = bytearray(W * H)
    seen = False
    deadline = time.time() + timeout
    with urllib.request.urlopen(f"http://{host}/stream", timeout=timeout) as res:
        buf = b""
        while time.time() < deadline:
            chunk = res.read1(65536)
            if not chunk:
                break
            buf += chunk
            while len(buf) >= 8:
                x, y, w, h = struct.unpack_from("<HHHH", buf)
                need = 8 + w * h
                if len(buf) < need:
                    break
                for row in range(h):
                    src = 8 + row * w
                    dst = (y + row) * W + x
                    panel[dst:dst + w] = buf[src:src + w]
                if w and h:
                    seen = True
                buf = buf[need:]
            if seen:
                return bytes(panel)
    raise SystemExit("no frame from the panel stream")


def png(path, grey, scale):
    rows = []
    for y in range(H):
        line = bytearray()
        for x in range(W):
            v = grey[y * W + x]
            line += bytes(c * v // 255 for c in AMBER) * scale
        rows.extend([b"\0" + bytes(line)] * scale)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", W * scale, H * scale, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(b"".join(rows), 9)))
        f.write(chunk(b"IEND", b""))


def press(host, key):
    for down in (True, False):
        req = urllib.request.Request(
            f"http://{host}/input", data=json.dumps({"key": key, "down": down}).encode(),
            headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=5).read()
        time.sleep(0.12)


args = sys.argv[1:]
host = "localhost:8899"
if args[:1] == ["--host"]:
    host, args = args[1], args[2:]
if args[:1] == ["shot"] and len(args) >= 2:
    scale = int(args[args.index("--scale") + 1]) if "--scale" in args else 3
    png(args[1], grab(host), scale)
    print(args[1])
elif args[:1] == ["press"] and len(args) >= 2:
    for k in args[1:]:
        press(host, k)
        time.sleep(0.4)
else:
    sys.exit(__doc__)
