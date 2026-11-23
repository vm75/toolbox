#!/usr/bin/env bash
set -Eeuo pipefail
command -v x86_64-w64-mingw32-gcc
make -C "$SRC" mingw64_defconfig
make -C "$SRC" -j"${TOOLBOX_JOBS:-4}" CROSS_COMPILE=x86_64-w64-mingw32-
[[ -s "$SRC/busybox.exe" ]] || exit 1
tar -C "$SRC" -czf "$OUT/busybox-windows-amd64.tgz" busybox.exe \
  -C "$ROOT/tools/busybox/assets" localrc sh.cmd
