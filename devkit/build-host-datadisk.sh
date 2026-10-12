#!/bin/bash
# Format the blank 40 GB data disk, mount it at /data, move build-heavy dirs there, add swap.
set -euo pipefail
S() { echo user | sudo -S -p "" "$@"; }
DISK=/dev/sdc
# Only ever a blank disk: no filesystem, no partitions.
if [ -z "$(lsblk -no FSTYPE "$DISK" | tr -d ' \n')" ] && [ "$(lsblk -no NAME "$DISK" | wc -l)" = 1 ]; then
	S mkfs.ext4 -q -L flipperdata "$DISK"
fi
S mkdir -p /data
grep -q 'LABEL=flipperdata' /etc/fstab || S sh -c "echo 'LABEL=flipperdata /data ext4 defaults,nofail 0 2' >> /etc/fstab"
mountpoint -q /data || S mount /data
S mkdir -p /data/user && S chown user:user /data/user
for d in src .cargo .rustup; do
	if [ -d "$HOME/$d" ] && [ ! -L "$HOME/$d" ]; then
		mv "$HOME/$d" /data/user/
		ln -s "/data/user/$d" "$HOME/$d"
	fi
done
if [ ! -f /data/swapfile ]; then
	S fallocate -l 4G /data/swapfile && S chmod 600 /data/swapfile && S mkswap -q /data/swapfile
	grep -q '/data/swapfile' /etc/fstab || S sh -c "echo '/data/swapfile none swap sw,nofail 0 0' >> /etc/fstab"
fi
S swapon /data/swapfile 2>/dev/null || true
df -h / /data | tail -2
free -m | grep -i swap
ls -la ~ | grep -E '\-> /data'
