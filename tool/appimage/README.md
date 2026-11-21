# AppImage (aarch64)

Builds a single-file AppImage from the official `linux-arm64` release bundle plus
a complete `libmpv.so.2` closure. Intended for Steam Frame / SteamOS ARM64, but
runs on any aarch64 glibc system with GTK3.

## Why a Debian trixie closure

The upstream bundle does not ship `libmpv`; `media_kit` opens `libmpv.so.2` by
name at runtime. Flathub's MPV app has `libmpv.so.2` too, but its ABI family is
different (`libplacebo.so.387`, `libcdio.so.21`, glibc 2.44) and its closure is
~171 MiB. Debian trixie matches the `libplacebo.so.349` / `libcdio.so.19` family,
requires at most `GLIBC_2.39`, and the closure is ~160 MiB unpacked.

`collect-libs.sh` resolves it automatically:

- downloads `libmpv2` and dependencies in an aarch64 Debian trixie container,
- walks the ELF `NEEDED` graph from the suite's own `libmpv`,
- fetches base libraries that are preinstalled in the container image,
- deliberately leaves glibc, the loader, compiler runtime, GPU stack, core X11,
  GTK/GLib, the **Wayland client stack** and the audio servers to the host.

The Wayland client libraries must come from the host: SteamOS's Mesa/EGL vendor
modules are built against the host Wayland ABI, and shadowing them makes
`eglGetProcAddress("eglGetPlatformDisplayEXT")` return NULL — which surfaces as
libepoxy's "No provider of eglGetPlatformDisplayEXT found" error.

## Build

Requirements: `podman`, `mksquashfs` (`squashfs-tools`), `binutils`, `curl`.
On x86_64, register `qemu-aarch64` binfmt; on an ARM64 host it is native.

```sh
curl -fL https://github.com/normalllll/BooruFlow/releases/latest/download/linux-arm64.tar.gz \
  -o build/input/linux-arm64.tar.gz

MODE=full ./tool/appimage/collect-libs.sh
VERSION=0.13.2+42 ./tool/appimage/build-appimage.sh
```

Output: `dist/BooruFlow-<version>-anylinux-aarch64.AppImage`.

`collect-libs.sh` also has a `MODE=minimal` (default) that only ships the
closure of the SONAMEs a target machine reported missing — useful when the plain
binary install is already present and `libmpv.so.2` exists.

## Verify

```sh
./tool/appimage/audit-bundle.sh dist/booruflow-libs-full-aarch64
./scripts/verify-aarch64.sh dist/booruflow-libs-full-aarch64/lib
```

## Runtime notes

`AppRun` sets `LD_LIBRARY_PATH`, `XDG_DATA_DIRS`, and disables the Gamescope WSI
implicit Vulkan layer (`VK_LAYER_FROG_gamescope_wsi_aarch64`). That layer tries
to hook libmpv's offscreen Vulkan swapchains and shows two blocking dialogs per
launch; Flutter renders through OpenGLES, so the layer is not needed.

`egl-diagnose.sh` prints the session type, EGL vendor JSON, installed EGL/Wayland
libraries and what the app loads — use it when a GTK/EGL startup issue appears on
new hardware.

## CI

`.github/workflows/appimage.yml` builds on `ubuntu-24.04-arm` (native, no qemu),
downloads the latest upstream release bundle, runs `collect-libs.sh` and uploads
the AppImage artifact.

## Automation

`.github/workflows/upstream-appimage.yml` runs every six hours and on demand:

1. Reads the latest release tag from `normalllll/BooruFlow`.
2. Skips when `appimage-<tag>` already exists in this repository.
3. Rebases `main` onto that tag, replaying the aarch64 Skia commit (linear history).
4. Builds the Linux ARM64 bundle on `ubuntu-24.04-arm`.
5. Collects and audits the libmpv closure, then builds the AppImage.
6. Publishes `appimage-<tag>` with the AppImage and its `.sha256`.

Manual run: **Actions → upstream-appimage → Run workflow**, with optional `tag`,
`force` (rebuild an existing release) and `publish` (off = artifact only).

Requirements and limits:

- Repository setting **Actions → Workflow permissions** must be *Read and write*.
- A rebase conflict fails the run; resolve it manually on `main`.
- The workflow force-pushes the rebased `main`. This is a build fork, so that is
  expected, but it rewrites history.
- Only the upstream *latest release* is considered, not prereleases or bare tags.
- GitHub disables scheduled workflows after 60 days without repository activity;
  a manual dispatch re-enables them.

