#!/bin/bash
# Set up the x86 build host (the Debian 13 VM in VMware) for Flipper One development.
# Safe to run again: every step checks what is already there.
#
#   ./flipper host 'bash -s' < devkit/build-host-setup.sh
#
# What you get, all under ~/src:
#   flipctl-slint                  the panel UI + app SDK, at the commit the image ships
#   flipctl-apps                   the App Manager catalogue's sources
#   flipperone-mcu-firmware        RP2350 co-processor firmware (+ ../pico-sdk 2.3.1)
#   flipperone-linux-build-scripts kernels, device-tree overlays, images
#   flipperone-testing             Flipper's test set (also on the device in /flipperone-testing)
# and on PATH (~/.local/bin):
#   mcu-build [target]             build the RP2350 firmware .uf2 (default target f1)
#   kernel-build                   build Flipper's mainline kernel .debs with their scripts
set -euo pipefail
IMAGE_FLIPCTL=27c2b071f129b02391a7529245228c19a884eda6   # flipctl-slint in image build 2315

sudo_() { echo user | sudo -S -p "" "$@"; }

echo "== packages"
sudo_ env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
	git curl ca-certificates build-essential pkg-config cmake ninja-build python3 python3-venv \
	desktop-file-utils squashfs-tools file rsync \
	gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross \
	bc bison flex libssl-dev libelf-dev dwarves cpio kmod device-tree-compiler u-boot-tools imagemagick \
	gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib >/dev/null

echo "== rust"
if [ ! -x ~/.cargo/bin/rustup ]; then
	curl -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal
fi
. ~/.cargo/env
rustup target add aarch64-unknown-linux-gnu >/dev/null

clone() {   # clone <repo> <dir> [ref] [--recursive]
	local repo=$1 dir=$2 ref=${3:-} extra=${4:-}
	if [ ! -d "$dir/.git" ]; then
		git clone -q $extra "https://github.com/$repo.git" "$dir"
	fi
	if [ -n "$ref" ]; then
		git -C "$dir" -c advice.detachedHead=false checkout -q "$ref"
		[ -z "$extra" ] || git -C "$dir" submodule update -q --init --recursive
	fi
}

echo "== sources"
mkdir -p ~/src && cd ~/src
clone flipperdevices/flipctl-slint flipctl-slint "$IMAGE_FLIPCTL"
clone flipperdevices/flipctl-apps flipctl-apps
clone flipperdevices/flipperone-mcu-firmware flipperone-mcu-firmware "" --recursive
clone raspberrypi/pico-sdk pico-sdk 2.3.1 --recursive
clone flipperdevices/flipperone-linux-build-scripts flipperone-linux-build-scripts
clone flipperdevices/flipperone-testing flipperone-testing

echo "== helpers"
mkdir -p ~/.local/bin
cat > ~/.local/bin/mcu-build <<'EOF'
#!/bin/bash
# Build Flipper One's RP2350 firmware: mcu-build [target]   (targets/ has f1, f2, ...)
set -euo pipefail
cd ~/src/flipperone-mcu-firmware
target=${1:-f1}
mkdir -p "build-$target" && cd "build-$target"
PICO_SDK_PATH=~/src/pico-sdk cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DFW_TARGET="$target" >/dev/null
cmake --build . --config Release --parallel
ls -la "$PWD"/*.uf2
EOF
cat > ~/.local/bin/kernel-build <<'EOF'
#!/bin/bash
# Build Flipper's mainline kernel (flipper-linux-kernel) with their own script, natively.
# The kernel tree is cloned on first use (shallow) and kept; KEEP_SRC=update pulls it.
# The .debs land in ~/src/flipperone-linux-build-scripts/prebuilt/linux.
set -euo pipefail
cd ~/src/flipperone-linux-build-scripts
KEEP_SRC=${KEEP_SRC:-yes} exec ./build-kernel-mainline.sh "$@"
EOF
chmod +x ~/.local/bin/mcu-build ~/.local/bin/kernel-build
grep -q '.local/bin' ~/.profile || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile

echo "== ready"
rustc --version
aarch64-linux-gnu-gcc --version | head -1
arm-none-eabi-gcc --version | head -1
ls ~/src
