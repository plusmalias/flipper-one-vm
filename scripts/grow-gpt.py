#!/usr/bin/env python3
"""Grow a raw GPT disk image and extend its last partition to fill it.

usage: grow-gpt.py IMAGE SIZE_GIB

The rootfs fstab carries x-systemd.growfs, so btrfs expands into the new
space on the next boot.
"""
import struct, sys, zlib

SECTOR = 512
img, gib = sys.argv[1], int(sys.argv[2])
total = gib * 2**30 // SECTOR

with open(img, "r+b") as f:
    f.seek(SECTOR)
    hdr = bytearray(f.read(SECTOR))
    assert hdr[:8] == b"EFI PART", "no GPT header"
    hsize = struct.unpack_from("<I", hdr, 12)[0]
    ent_lba, n_ent, ent_size = struct.unpack_from("<QII", hdr, 72)
    ent_sectors = (n_ent * ent_size + SECTOR - 1) // SECTOR

    f.seek(0, 2)
    if f.tell() // SECTOR > total:
        sys.exit("image is already bigger than %d GiB" % gib)

    f.seek(ent_lba * SECTOR)
    ents = bytearray(f.read(n_ent * ent_size))
    last_used = max(i for i in range(n_ent) if ents[i * ent_size:i * ent_size + 16] != bytes(16))

    backup_lba = total - 1
    backup_ent_lba = backup_lba - ent_sectors
    last_usable = backup_ent_lba - 1
    struct.pack_into("<Q", ents, last_used * ent_size + 40, last_usable)
    ents_crc = zlib.crc32(ents) & 0xFFFFFFFF

    def header(current, other, entries_at):
        h = bytearray(hdr[:hsize])
        struct.pack_into("<QQ", h, 24, current, other)
        struct.pack_into("<Q", h, 48, last_usable)
        struct.pack_into("<Q", h, 72, entries_at)
        struct.pack_into("<I", h, 88, ents_crc)
        struct.pack_into("<I", h, 16, 0)
        struct.pack_into("<I", h, 16, zlib.crc32(h) & 0xFFFFFFFF)
        return bytes(h) + bytes(SECTOR - hsize)

    f.truncate(total * SECTOR)
    f.seek(ent_lba * SECTOR); f.write(ents)
    f.seek(SECTOR); f.write(header(1, backup_lba, ent_lba))
    f.seek(backup_ent_lba * SECTOR); f.write(ents)
    f.seek(backup_lba * SECTOR); f.write(header(backup_lba, 1, backup_ent_lba))
    # Protective MBR: partition 1 spans the whole disk (capped at 2 TiB).
    f.seek(446 + 12); f.write(struct.pack("<I", min(total - 1, 0xFFFFFFFF)))

print("grew %s to %d GiB; partition %d now ends at LBA %d" % (img, gib, last_used + 1, last_usable))
