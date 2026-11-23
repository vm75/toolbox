#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$TARGET" == android-arm64 ]]; then
  # Native Android library is built by dependent Librera's existing integration.
  # A direct MuPDF invocation exports the patched source snapshot for inspection.
  tar --exclude=.git -C "$SRC" -czf "$OUT/mupdf-patched-source.tar.gz" .
else
  make -C "$SRC" -j"${TOOLBOX_JOBS:-4}" build=release libs
  find "$SRC/build" -type f \( -name 'libmupdf*.a' -o -name 'libmupdf*.so' \) -exec cp -v {} "$OUT/" \;
fi
