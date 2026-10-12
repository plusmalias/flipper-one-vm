#!/usr/bin/env python3
"""Build the VM's initramfs and modules disk from an unpacked Debian arm64 kernel .deb.

Outputs (in kernel/):
  initrd.img    gzip'd newc cpio: busybox, /init, virtio_blk + btrfs and their deps
  modules.tar   ustar of usr/lib/modules/<kver>, attached as a raw virtio disk and
                unpacked into each profile on its first boot (see scripts/init)
"""
import gzip, io, lzma, os, re, stat, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(HERE)
KDIR = os.path.join(TOP, "kernel")
DEB = os.path.join(KDIR, "deb-kernel")
BUSYBOX = os.path.join(KDIR, "deb-bb", "usr", "bin", "busybox")
# crc32c/xxhash/blake2b are only softdeps of libcrc32c and btrfs, so list them first
WANT = ["virtio_blk", "crc32c_generic", "xxhash_generic", "blake2b_generic", "btrfs"]

kver = os.listdir(os.path.join(DEB, "usr", "lib", "modules"))
assert len(kver) == 1, kver
kver = kver[0]
moddir = os.path.join(DEB, "usr", "lib", "modules", kver)

paths = {}
for root, _, files in os.walk(os.path.join(moddir, "kernel")):
    for f in files:
        name = re.sub(r"\.ko(\.xz|\.zst|\.gz)?$", "", f).replace("-", "_")
        paths[name] = os.path.join(root, f)

def load(name):
    p = paths[name]
    data = open(p, "rb").read()
    return lzma.decompress(data) if p.endswith(".xz") else data

def deps(blob):
    m = re.search(rb"\0depends=([^\0]*)\0", blob)
    return [d.decode().replace("-", "_") for d in m.group(1).split(b",") if d] if m else []

order, blobs = [], {}
def visit(name):
    if name in blobs:
        return
    blobs[name] = load(name)
    for d in deps(blobs[name]):
        visit(d)
    order.append(name)
for w in WANT:
    visit(w)
print("initramfs modules:", " ".join(order))


class Cpio:
    def __init__(self):
        self.buf, self.ino = io.BytesIO(), 1

    def add(self, name, mode, data=b"", rdev=(0, 0)):
        name_b = name.encode() + b"\0"
        hdr = "070701" + "".join("%08X" % v for v in (
            self.ino, mode, 0, 0, 1, 0, len(data), 0, 0, rdev[0], rdev[1], len(name_b), 0))
        self.ino += 1
        self.buf.write(hdr.encode() + name_b)
        self.buf.write(b"\0" * (-(110 + len(name_b)) % 4))
        self.buf.write(data)
        self.buf.write(b"\0" * (-len(data) % 4))

    def finish(self):
        self.add("TRAILER!!!", 0)
        return self.buf.getvalue()


c = Cpio()
for d in ["bin", "dev", "proc", "sys", "newroot", "lib", "lib/modules"]:
    c.add(d, stat.S_IFDIR | 0o755)
c.add("dev/console", stat.S_IFCHR | 0o600, rdev=(5, 1))
c.add("bin/busybox", stat.S_IFREG | 0o755, open(BUSYBOX, "rb").read())
c.add("bin/sh", stat.S_IFLNK | 0o777, b"busybox")
c.add("init", stat.S_IFREG | 0o755, open(os.path.join(HERE, "init"), "rb").read())
for name in order:
    c.add("lib/modules/%s.ko" % name, stat.S_IFREG | 0o644, blobs[name])
c.add("lib/modules/load-order", stat.S_IFREG | 0o644, ("\n".join(order) + "\n").encode())

out = os.path.join(KDIR, "initrd.img")
with open(out, "wb") as f:
    f.write(gzip.compress(c.finish(), 9))
print("wrote", out, os.path.getsize(out), "bytes")

tar = os.path.join(KDIR, "modules.tar")
env = dict(os.environ, COPYFILE_DISABLE="1")
# The kernel image rides along as <kver>/vmlinuz, where Flipper's own boot entries keep
# theirs: boot-profile wants the file an entry names to exist, even for a soft-reboot.
subprocess.check_call(["bsdtar", "--format", "ustar", "--uid", "0", "--gid", "0",
                       "--uname", "root", "--gname", "root", "--no-xattrs", "--no-mac-metadata",
                       "-s", f"|^vmlinuz-{re.escape(kver)}$|{kver}/vmlinuz|",
                       "-cf", tar, "-C", os.path.join(DEB, "usr", "lib", "modules"), kver,
                       "-C", os.path.join(DEB, "boot"), "vmlinuz-" + kver], env=env)
print("wrote", tar, os.path.getsize(tar), "bytes")
kimg = os.path.join(DEB, "boot", "vmlinuz-" + kver)
link = os.path.join(KDIR, "vmlinuz")
if os.path.lexists(link):
    os.remove(link)
os.symlink(os.path.relpath(kimg, KDIR), link)
print("kernel", kver, "->", link)
