#!/usr/bin/env bash
# Static closure audit: every NEEDED of every bundled object must resolve to the
# bundle or to the small host allowlist. No execution, no qemu.
# usage: audit-bundle.sh BUNDLE_DIR
set -euo pipefail

dir=${1:?usage: audit-bundle.sh BUNDLE_DIR}/lib
[ -d "$dir" ] || { echo "no lib dir: $dir" >&2; exit 2; }

# Libraries SteamOS provides and we deliberately do not bundle. libjvm is only
# referenced by libdartjni.so (Android path); there is no JVM on SteamOS.
HOST='^(ld-linux.*|libc\.so.*|libm\.so.*|libmvec.*|libpthread.*|libdl.*|librt.*|libresolv.*|libutil\.so.*|libgcc_s.*|libstdc\+\+.*|libvulkan.*|libGL.*|libEGL.*|libgbm.*|libdrm.*|libgtk.*|libgdk.*|libcairo.*|libpango.*|libpangocairo.*|libgdk_pixbuf.*|libharfbuzz.*|libfreetype.*|libfontconfig.*|libfribidi.*|libglib.*|libgobject.*|libgio.*|libgmodule.*|libatk.*|libepoxy.*|libjvm.*|libX11.*|libXext.*|libXcursor.*|libXi\.so.*|libXrandr.*|libXfixes.*|libxcb.*|libwayland.*|libxkbcommon.*|libasound.*|libpulse.*|libpipewire.*|libjack.*|libopenal.*|libz\.so.*|libzstd.*|liblz4.*|liblzma.*|libbz2.*|libffi.*|libgmp.*|libnettle.*|libhogweed.*|libssl.*|libcrypto.*|libudev.*|libcap\.so.*|libxxhash.*|libacl.*|libncursesw.*|libtinfo.*)$'

bad=0
for f in "$dir"/*.so*; do
  [ -e "$f" ] || continue
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    [ -e "$dir/$n" ] && continue
    grep -Eq "$HOST" <<<"$n" && continue
    printf '  %-40s needed by %s\n' "$n" "$(basename "$f")"
    bad=1
  done < <(readelf -d "$f" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
done

if [ "$bad" -ne 0 ]; then
  echo
  echo "FAIL: unresolved NEEDED outside the bundle and host allowlist."
  exit 1
fi
echo "PASS: all NEEDED resolve to the bundle or the host allowlist."
