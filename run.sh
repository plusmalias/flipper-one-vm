#!/bin/bash
# Run the Flipper One (FlipperOS, Debian 13 arm64) image in an emulated arm64 VM.
#
#   ./run.sh [PROFILE] [--headless | --background] [--rdshell] [--reset]
#
# PROFILE   Desktop (default), Minimal, No-Graphics, TV-Media-Box, Router
#           = the btrfs root subvolumes the real boot menu offers.
# --headless    no window; the serial console runs in this terminal (Ctrl-A X quits)
# --background  no window, detached; log in with ./ssh.sh
#               serial log: run/serial.log, console socket: run/serial.sock
# --rdshell     stop in the initramfs shell before switching to the root
# --reset       throw away all changes and go back to the factory image
#
# Env: CPUS (4), MEM (4G), SSH_PORT (2222), SCREEN_PORT (8899)
set -euo pipefail
cd "$(dirname "$0")"

PROFILE=Desktop MODE=window EXTRA=
for a in "$@"; do
	case "$a" in
		--headless) MODE=headless ;;
		--background) MODE=background ;;
		--rdshell) EXTRA="$EXTRA rdshell" ;;
		--reset) RESET=1 ;;
		-h|--help) sed -n '2,17p' "$0"; exit 0 ;;
		-*) echo "unknown option $a" >&2; exit 1 ;;
		*) PROFILE=${a#@} ;;
	esac
done
case "$PROFILE" in
	Desktop|Minimal|No-Graphics|TV-Media-Box|Router) ;;
	*) echo "unknown profile '$PROFILE' (Desktop, Minimal, No-Graphics, TV-Media-Box, Router)" >&2; exit 1 ;;
esac

QEMU=qemu/bin/qemu-system-aarch64
TZNAME=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
if [ -f run/qemu.pid ] && kill -0 "$(cat run/qemu.pid)" 2>/dev/null || pgrep -qf "$PWD/$QEMU|^$QEMU"; then
	echo "The VM is already running. Stop it first: ./ssh.sh sudo poweroff  (or quit its window)" >&2
	exit 1
fi
FACTORY=images/flipper-one-2315-factory.qcow2
DISK=images/flipper-one.qcow2
mkdir -p run

if [ -n "${RESET:-}" ] || [ ! -f "$DISK" ]; then
	echo "Creating a fresh disk from $FACTORY"
	rm -f "$DISK"
	qemu/bin/qemu-img create -q -f qcow2 -b "$(basename "$FACTORY")" -F qcow2 "$DISK"
fi

args=(
	-name "Flipper One ($PROFILE)"
	-M virt -cpu cortex-a72 -smp "${CPUS:-4}" -m "${MEM:-4G}"
	-accel tcg,thread=multi,tb-size=1024
	-kernel kernel/vmlinuz -initrd kernel/initrd.img
	# No USB device controller in a VM, and the root partition already fills the disk.
	-append "root=/dev/vda3 rootflags=subvol=@$PROFILE rw console=tty0 console=ttyAMA0 loglevel=4 systemd.mask=usb-ncm-msc-mtp-gadget.service systemd.mask=systemd-repart.service systemd.mask=fio.service flippervm.tz=$TZNAME$EXTRA"
	-drive "file=$DISK,if=none,id=root,format=qcow2,discard=unmap"
	-device virtio-blk-pci,drive=root
	-drive file=kernel/modules.tar,if=none,id=mods,format=raw,readonly=on
	-device virtio-blk-pci,drive=mods
	-netdev "user,id=net0,hostname=flipper-one-vm,hostfwd=tcp:127.0.0.1:${SSH_PORT:-2222}-:22,hostfwd=tcp:127.0.0.1:${SCREEN_PORT:-8899}-:8899"
	-device virtio-net-pci,netdev=net0
	-device virtio-rng-pci
	-device virtio-gpu-pci
	-device qemu-xhci -device usb-kbd -device usb-tablet
	-qmp unix:run/qmp.sock,server=on,wait=off
)

echo "Booting @$PROFILE (emulated arm64 — expect a slow boot)."
echo "  Flipper One screen: http://localhost:${SCREEN_PORT:-8899}/   SSH: ./ssh.sh  (user / user)"
case "$MODE" in
	window)
		exec "$QEMU" "${args[@]}" -display cocoa \
			-chardev vc,id=s0,logfile=run/serial.log -serial chardev:s0 ;;
	headless)
		exec "$QEMU" "${args[@]}" -nographic ;;
	background)
		"$QEMU" "${args[@]}" -display none -daemonize -pidfile run/qemu.pid \
			-chardev socket,id=s0,path=run/serial.sock,server=on,wait=off,logfile=run/serial.log \
			-serial chardev:s0
		echo "Running in the background (pid $(cat run/qemu.pid)). Stop with: ./ssh.sh sudo poweroff" ;;
esac
