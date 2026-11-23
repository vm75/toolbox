#!/usr/bin/env bash
set -Eeuo pipefail
cd "$SRC/src"
./configure
make -j"${TOOLBOX_JOBS:-4}"
[[ -x "$SRC/run/john" ]] || exit 1
tar -C "$SRC" -czf "$OUT/john-linux-amd64.tgz" run
