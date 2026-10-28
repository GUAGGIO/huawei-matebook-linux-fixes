#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== [1/4] Installing required packages (alsa-tools, alsa-utils, zstd, python3) ==="
apt-get update
apt-get install -y alsa-tools alsa-utils zstd python3 binutils
apt-mark manual alsa-tools alsa-utils zstd

echo "=== [2/4] Installing kernel postinst hook for ESSX8336 ACPI ghost device ==="
install -m 0755 "$SCRIPT_DIR/zz-huawei-audio-patch" /etc/kernel/postinst.d/zz-huawei-audio-patch

echo "=== [3/4] Patching currently installed kernels ==="
for kdir in /lib/modules/*; do
    if [ -d "$kdir" ]; then
        kver="$(basename "$kdir")"
        echo "Checking kernel $kver..."
        /etc/kernel/postinst.d/zz-huawei-audio-patch "$kver"
    fi
done
update-initramfs -u -k all || true

echo "=== [4/4] Installing HDA soundcard & headphones monitor service ==="
install -m 0755 "$SCRIPT_DIR/huawei-soundcard-headphones-monitor.sh" /usr/local/bin/huawei-soundcard-headphones-monitor.sh
install -m 0644 "$SCRIPT_DIR/huawei-soundcard-headphones-monitor.service" /etc/systemd/system/huawei-soundcard-headphones-monitor.service

systemctl daemon-reload
systemctl enable --now huawei-soundcard-headphones-monitor.service

echo "=== Audio & Kernel fix installed successfully! Please reboot if this is the first installation. ==="
