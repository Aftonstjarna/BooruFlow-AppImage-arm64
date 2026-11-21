#!/bin/sh
# Run on Steam Frame. Read-only diagnostics for:
#   "No provider of eglGetPlatformDisplayEXT found. Requires one of: EGL_EXT_platform_base"
# usage: ./egl-diagnose.sh [path-to-AppImage]
set -u

APP=${1:-$HOME/Applications/BooruFlow-0.13.0+40-anylinux-aarch64.AppImage}

echo "== session"
echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-}"

echo
echo "== EGL vendor config"
if [ -d /usr/share/glvnd/egl_vendor.d ]; then
  ls -l /usr/share/glvnd/egl_vendor.d
  for f in /usr/share/glvnd/egl_vendor.d/*.json; do
    [ -e "$f" ] || continue
    echo "-- $f"
    cat "$f"
  done
else
  echo "no /usr/share/glvnd/egl_vendor.d (Mesa may provide libEGL directly)"
fi

echo
echo "== EGL / GL / GBM libraries"
find /usr/lib /usr/lib64 -maxdepth 3 \
  \( -name 'libEGL*' -o -name 'libGLX*' -o -name 'libGLdispatch*' -o -name 'libgbm*' \) \
  2>/dev/null | sort

echo
echo "== Wayland libraries"
find /usr/lib /usr/lib64 -maxdepth 3 -name 'libwayland*' 2>/dev/null | sort

echo
echo "== what the app loads"
if [ -f "$APP" ]; then
  LD_DEBUG=libs "$APP" 2>&1 \
    | grep -E 'libEGL|libwayland|libgbm|libdrm|libGL' \
    | sed 's/^/  /' | head -80
else
  echo "not found: $APP"
fi

cat <<'EOF'

Next, try these three launches and note which changes the error:

  # force the Mesa EGL vendor (if the default is the Qualcomm one)
  __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json "$APP"

  # use XWayland + GLX instead of EGL on Wayland
  GDK_BACKEND=x11 "$APP"

  # software GL, to confirm the failure is in the GL driver path
  LIBGL_ALWAYS_SOFTWARE=1 "$APP"
EOF
