#!/usr/bin/env bash
set -Eeuo pipefail
cd "$SRC"
if [[ ! -x ./configure ]]; then
  if [[ -x ./prepare-source ]]; then ./prepare-source; else autoreconf -fi; fi
fi
./configure
make -j"${TOOLBOX_JOBS:-4}"
[[ -s ./rsync ]] || exit 1
tar -czf "$OUT/rsync-linux-amd64.tgz" rsync
