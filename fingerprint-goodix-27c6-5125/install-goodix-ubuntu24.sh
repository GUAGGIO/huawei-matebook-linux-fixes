#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d /tmp/goodix-27c6-5125-build.XXXXXX)"
REAL_USER="${SUDO_USER:-$USER}"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "=== [1/6] Installing build and runtime dependencies (Ubuntu 22.04 / 24.04+) ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update

SYSTEMD_DEV=libsystemd-dev
apt-cache show systemd-dev >/dev/null 2>&1 && SYSTEMD_DEV=systemd-dev

GIREPO_DEV=libgirepository1.0-dev
apt-cache show libgirepository-2.0-dev >/dev/null 2>&1 && GIREPO_DEV=libgirepository-2.0-dev

apt-get install -y \
    build-essential meson ninja-build gcc g++ pkg-config python3 dos2unix curl ca-certificates \
    libglib2.0-dev libgusb-dev libusb-1.0-0-dev libpixman-1-dev \
    libmbedtls-dev libssl-dev zlib1g-dev libudev-dev \
    gobject-introspection "$GIREPO_DEV" \
    libopencv-dev doctest-dev "$SYSTEMD_DEV" \
    fprintd libpam-fprintd

echo "=== [2/6] Fetching goodix-linux-27c6-5125 and libfprint (SIGFM) sources ==="
mkdir -p "$WORK_DIR/goodix" "$WORK_DIR/goodix/libfprint"
curl -sL https://github.com/Rockytkg/goodix-linux-27c6-5125/archive/refs/heads/master.tar.gz | tar -xz --strip-components=1 -C "$WORK_DIR/goodix"
curl -sL https://github.com/abb128/libfprint/archive/50d26fb3f22dde2cef3ebefbe4fd2cefd1b2fb56.tar.gz | tar -xz --strip-components=1 -C "$WORK_DIR/goodix/libfprint"

echo "=== [3/6] Integrating goodixgf driver and applying Ubuntu 24.04 Meson patches ==="
GOODIX_DIR="$WORK_DIR/goodix"
SRC="$GOODIX_DIR/libfprint"
D="$SRC/libfprint/drivers/goodixgf"
mkdir -p "$D/core"

cp "$GOODIX_DIR/src/goodixgf.c" "$D/"
cp "$GOODIX_DIR/src/transport.c" \
   "$GOODIX_DIR/src/goodix_frame.c" \
   "$GOODIX_DIR/src/goodix_cmd.c" \
   "$GOODIX_DIR/src/goodix_psk.c" \
   "$GOODIX_DIR/src/goodix_tls.c" \
   "$GOODIX_DIR/src/goodix_image.c" \
   "$GOODIX_DIR/src/goodix_calib.c" \
   "$GOODIX_DIR/src/goodix_capture.c" \
   "$D/core/"
cp "$GOODIX_DIR/include/goodix_dev.h" \
   "$GOODIX_DIR/include/transport.h" \
   "$GOODIX_DIR/include/goodix_proto.h" \
   "$GOODIX_DIR/include/goodix_frame.h" \
   "$GOODIX_DIR/include/goodix_cmd.h" \
   "$GOODIX_DIR/include/goodix_psk.h" \
   "$GOODIX_DIR/include/goodix_tls.h" \
   "$GOODIX_DIR/include/goodix_image.h" \
   "$GOODIX_DIR/include/goodix_calib.h" \
   "$GOODIX_DIR/include/goodix_capture.h" \
   "$D/core/"

python3 - "$SRC" << 'PYEOF'
import sys, pathlib

src = pathlib.Path(sys.argv[1])

# 1. Patch root meson.build for goodixgf dependencies (mbedtls, zlib, libusb-1.0)
root_meson = src / "meson.build"
s = root_meson.read_text()
if "'goodixgf'" not in s:
    s = s.replace("'goodixmoc',\n", "'goodixmoc',\n    'goodixgf',\n", 1)
    anchor = "if udev_rules.disabled()\n"
    block = """if 'goodixgf' in drivers
    libusb_dep   = dependency('libusb-1.0', required: true)
    zlib_dep     = dependency('zlib', required: true)
    mbedcrypto_d = cc.find_library('mbedcrypto', required: true)
    mbedtls_d    = cc.find_library('mbedtls', required: true)
    mbedx509_d   = cc.find_library('mbedx509', required: true)
    deps += [libusb_dep, zlib_dep, mbedcrypto_d, mbedtls_d, mbedx509_d]
endif

"""
    s = s.replace(anchor, block + anchor, 1)
    root_meson.write_text(s)

# 2. Patch libfprint/meson.build for goodixgf sources
lib_meson = src / "libfprint" / "meson.build"
s2 = lib_meson.read_text()
if "'goodixgf'" not in s2:
    anchor2 = "if 'goodixmoc' in drivers\n"
    block2 = """if 'goodixgf' in drivers
    drivers_sources += [
        'drivers/goodixgf/goodixgf.c',
        'drivers/goodixgf/core/transport.c',
        'drivers/goodixgf/core/goodix_frame.c',
        'drivers/goodixgf/core/goodix_cmd.c',
        'drivers/goodixgf/core/goodix_psk.c',
        'drivers/goodixgf/core/goodix_tls.c',
        'drivers/goodixgf/core/goodix_image.c',
        'drivers/goodixgf/core/goodix_calib.c',
        'drivers/goodixgf/core/goodix_capture.c',
    ]
endif
"""
    s2 = s2.replace(anchor2, block2 + anchor2, 1)
    lib_meson.write_text(s2)

# 3. Patch libfprint/sigfm/meson.build so doctest without .pc doesn't break Ubuntu 24.04 builds
sigfm_meson = src / "libfprint" / "sigfm" / "meson.build"
sigfm_meson.write_text("""sigfm_sources = [
    'sigfm.cpp',
    'binary.hpp',
    'sigfm.h'
]
doctest = dependency('doctest', required: false, version: ['>=2.0.0', '<3.0.0'])

libsigfm = static_library('sigfm',
        sigfm_sources,
        dependencies: [opencv],
)
if doctest.found()
  sigfm_tests = executable('sigfm-tests', ['./tests.cpp'], dependencies: [doctest, opencv], link_with: libsigfm)
  test('sigfm-tests', sigfm_tests)
endif
""")
PYEOF

echo "=== [4/6] Building and installing libfprint ==="
LIBDIR="lib/$(gcc -dumpmachine)"
export PKG_CONFIG_PATH="$SCRIPT_DIR:${PKG_CONFIG_PATH:-}"
cd "$SRC"
meson setup build \
    --prefix=/usr --libdir="$LIBDIR" \
    -Ddrivers=goodixgf -Ddoc=false \
    -Dudev_rules=enabled -Dudev_hwdb=enabled \
    -Dintrospection=true
ninja -C build
ninja -C build install
ldconfig
apt-mark hold libfprint-2-2t64 libfprint-2-2 2>/dev/null || true

echo "=== [5/6] Configuring udev rules and fprintd keepalive ==="
install -m 0644 "$SCRIPT_DIR/70-goodix.rules" /etc/udev/rules.d/70-goodix.rules
udevadm control --reload-rules
udevadm trigger

FPRINTD_SVC=/usr/lib/systemd/system/fprintd.service
FPRINTD_DROPIN=/etc/systemd/system/fprintd.service.d/keepalive.conf
if [ -f "$FPRINTD_SVC" ]; then
    FPRINTD_EXEC="$(sed -n 's/^ExecStart=//p' "$FPRINTD_SVC" | head -1)"
    FPRINTD_EXEC="${FPRINTD_EXEC%% *}"
    if [ -n "$FPRINTD_EXEC" ] && [ -x "$FPRINTD_EXEC" ]; then
        mkdir -p "$(dirname "$FPRINTD_DROPIN")"
        printf '[Service]\nExecStart=\nExecStart=%s --no-timeout\n' "$FPRINTD_EXEC" > "$FPRINTD_DROPIN"
        systemctl daemon-reload
    fi
fi
systemctl restart fprintd

echo "=== [6/6] Updating PAM fingerprint retry & timeout parameters ==="
"$SCRIPT_DIR/update_pam_tries.sh" || true

echo "=== Goodix 27c6:5125 Fingerprint Driver installed successfully! ==="
fprintd-list "$REAL_USER" || true
