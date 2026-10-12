#!/bin/bash
# Developer tools for a FlipperOS profile (run on the Flipper, as root, in the profile
# that should have them - each profile is its own root filesystem).
#
#   sudo ./flipper-devkit.sh            everything below
#   sudo ./flipper-devkit.sh core py    just some groups
#
# Packages that this Debian doesn't carry are skipped with a note, so it is safe to
# run again after an update; FlipperOS snapshots the profile before apt changes it.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

declare -A PKGS=(
	[core]="git git-lfs build-essential gcc g++ clang lld make cmake meson ninja-build pkg-config autoconf automake libtool bison flex bc"
	[debug]="gdb strace ltrace valgrind lsof psmisc sysstat linux-perf"
	[py]="python3-dev python3-venv python3-pip pipx ipython3 python3-pytest"
	[rust]="rustc cargo"
	[hw]="device-tree-compiler i2c-tools gpiod libgpiod-dev usbutils pciutils evtest picocom minicom can-utils"
	[kernel]="linux-headers-$(uname -r) kmod"
	[util]="vim nano tmux htop jq tree ripgrep fd-find curl wget rsync zip unzip file man-db less bash-completion"
	[gui]="kate konsole"
)
ORDER="core debug py rust hw kernel util gui"
[ $# -gt 0 ] && ORDER="$*"

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
echo "== $(date '+%F %T') devkit for $(findmnt -no SOURCE /) =="
apt-get update -q || true

for group in $ORDER; do
	want=(${PKGS[$group]:-})
	have=() missing=()
	for pkg in "${want[@]}"; do
		if apt-cache show "$pkg" >/dev/null 2>&1; then have+=("$pkg"); else missing+=("$pkg"); fi
	done
	echo "-- $group: ${have[*]:-nothing to install}"
	[ ${#missing[@]} -eq 0 ] || echo "   not available here: ${missing[*]}"
	[ ${#have[@]} -gt 0 ] || continue
	extra=()
	# Rust: trixie's own is old, the backport tracks stable.
	[ "$group" = rust ] && extra=(-t trixie-backports)
	apt-get install -y -q --no-install-recommends "${extra[@]}" "${have[@]}" \
		|| echo "   !! $group did not install cleanly"
done
echo "== $(date '+%F %T') done =="
