#!/usr/bin/env bash
set -Eeuo pipefail
command -v x86_64-w64-mingw32-gcc
# Current BusyBox-w32 preserves Windows environment-variable backslashes.
# Fail explicitly if upstream restores the conversion that our obsolete patch removed.
if grep -Fq 'bs_to_slash(end+1)' "$SRC/shell/ash.c"; then
  echo "BusyBox-w32 rewrites Windows environment-variable backslashes; review upstream ash.c" >&2
  exit 1
fi
make -C "$SRC" mingw64_defconfig
make -C "$SRC" -j"${TOOLBOX_JOBS:-4}" CROSS_COMPILE=x86_64-w64-mingw32-
[[ -s "$SRC/busybox.exe" ]] || exit 1
tar -C "$SRC" -czf "$OUT/busybox-windows-amd64.tgz" busybox.exe \
  -C "$ROOT/tools/busybox/assets" localrc sh.cmd
