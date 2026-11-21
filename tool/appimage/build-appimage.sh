#!/usr/bin/env bash
# Build a complete aarch64 AppImage for BooruFlow.
#
# Layout: official linux-arm64 release bundle + the full Debian trixie libmpv
# closure, packed as SquashFS and prefixed with the aarch64 uruntime. The
# SquashFS is built by the host (architecture-independent); only the runtime
# and payload are aarch64.
#
# Run from the repository root:
#   MODE=full ./tool/appimage/collect-libs.sh
#   ./tool/appimage/build-appimage.sh
#
# env: TARBALL, LIBS, OUT, VERSION, RUNTIME, RUNTIME_URL
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
version=${VERSION:-0.13.2+42}
tarball=${TARBALL:-$root/build/input/linux-arm64.tar.gz}
libs=${LIBS:-$root/dist/booruflow-libs-full-aarch64/lib}
out=${OUT:-$root/dist/BooruFlow-${version}-anylinux-aarch64.AppImage}
runtime_url=${RUNTIME_URL:-https://github.com/VHSgunzo/uruntime/releases/download/v0.8.4/uruntime-appimage-aarch64}
runtime=${RUNTIME:-$root/build/vendor/uruntime-appimage-aarch64}
work=$root/build/booruflow-appimage
appdir=$work/AppDir

[ -f "$tarball" ] || { echo "missing release bundle: $tarball (set TARBALL=...)" >&2; exit 2; }
[ -d "$libs" ] || { echo "missing lib set: $libs (run MODE=full ./tool/appimage/collect-libs.sh)" >&2; exit 2; }

if [ ! -f "$runtime" ]; then
  echo "==> fetching uruntime (aarch64)"
  mkdir -p "$(dirname "$runtime")"
  curl -fL "$runtime_url" -o "$runtime"
fi
machine=$(readelf -h "$runtime" | awk -F: '/Machine:/{gsub(/^[ \t]+/,"",$2); print $2}')
[ "$machine" = "AArch64" ] || { echo "runtime is $machine, expected AArch64" >&2; exit 1; }

echo "==> staging AppDir"
rm -rf "$work"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
         "$appdir/usr/share/icons/hicolor/512x512/apps"

tar xzf "$tarball" -C "$appdir/usr/bin"
[ -x "$appdir/usr/bin/booruflow" ] || { echo "unexpected bundle layout" >&2; exit 1; }

echo "==> adding full libmpv closure"
cp -a "$libs/." "$appdir/usr/bin/lib/"
# media_kit asks for libmpv.so.2; provide the unversioned name too.
ln -sf libmpv.so.2 "$appdir/usr/bin/lib/libmpv.so"

install -m644 "$appdir/usr/bin/data/app_icon.png" "$appdir/booruflow.png"
install -m644 "$appdir/usr/bin/data/app_icon.png" \
  "$appdir/usr/share/icons/hicolor/512x512/apps/booruflow.png"

cat > "$appdir/booruflow.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=BooruFlow
Comment=Booru browser and viewer
Exec=booruflow
Icon=booruflow
Terminal=false
Categories=Graphics;Network;
EOF
install -m644 "$appdir/booruflow.desktop" "$appdir/usr/share/applications/booruflow.desktop"

cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
set -eu
here=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$here/usr/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="$here/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# The global Gamescope WSI implicit layer cannot hook the offscreen Vulkan
# swapchains libmpv creates, and pops two blocking dialogs per launch:
#   "Hooking has failed somewhere! You may have a bad Vulkan layer interfering."
# Flutter renders through OpenGLES, so this layer buys this app nothing.
export VK_LOADER_LAYERS_DISABLE="${VK_LOADER_LAYERS_DISABLE:-VK_LAYER_FROG_gamescope_wsi_aarch64}"

exec "$here/usr/bin/booruflow" "$@"
EOF
chmod +x "$appdir/AppRun"

echo "==> packing SquashFS"
rm -f "$work/payload.squashfs"
mksquashfs "$appdir" "$work/payload.squashfs" \
  -comp zstd -Xcompression-level 19 -b 131072 \
  -noappend -root-owned -no-progress >/dev/null

echo "==> assembling AppImage"
mkdir -p "$(dirname "$out")"
cat "$runtime" "$work/payload.squashfs" > "$out"
chmod +x "$out"

echo "runtime: $(stat -c%s "$runtime") bytes"
echo -n "offset:  "
qemu-aarch64-static "$out" --appimage-offset 2>/dev/null || echo "(run on aarch64)"
file "$out"
ls -lh "$out"
sha256sum "$out"
