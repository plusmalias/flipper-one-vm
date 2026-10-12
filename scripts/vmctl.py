#!/usr/bin/env python3
"""Poke a running Flipper One VM (started by run.sh) over QMP / the serial socket.

  vmctl.py screenshot out.png     save the VM's display as a PNG
  vmctl.py powerdown              ask the guest to shut down (ACPI power button)
  vmctl.py serial 'text'          type a line on the serial console (--background mode)
"""
import json, os, socket, sys

RUN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "run")


def qmp(*cmds):
    s = socket.socket(socket.AF_UNIX)
    s.connect(os.path.join(RUN, "qmp.sock"))
    f = s.makefile("rw")
    json.loads(f.readline())  # greeting
    out = []
    for cmd in ({"execute": "qmp_capabilities"},) + cmds:
        f.write(json.dumps(cmd) + "\n"); f.flush()
        while True:
            r = json.loads(f.readline())
            if "return" in r or "error" in r:
                out.append(r)
                break
    return out[1:]


cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "screenshot":
    path = os.path.abspath(sys.argv[2])
    print(qmp({"execute": "screendump", "arguments": {"filename": path, "format": "png"}}))
elif cmd == "powerdown":
    print(qmp({"execute": "system_powerdown"}))
elif cmd == "serial":
    s = socket.socket(socket.AF_UNIX)
    s.connect(os.path.join(RUN, "serial.sock"))
    s.sendall(sys.argv[2].encode() + b"\r")
    s.close()
else:
    sys.exit(__doc__)
