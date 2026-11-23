#!/usr/bin/env bash
set -Eeuo pipefail
# Reuse Maestro's Entware AArch64 cross-toolchain, not the host glibc.
cache="${TOOLBOX_NGINX_CACHE:-$WORKSPACE/nginx-cache}"
entware="$cache/Entware"
if ! compgen -G "$entware/staging_dir/toolchain-*/bin/*g++" > /dev/null; then
  bash "$ROOT/tools/nginx/upstream-builder.sh" --toolchain-only --jobs "${TOOLBOX_JOBS:-4}" --workdir "$cache"
fi
shopt -s nullglob
compilers=("$entware"/staging_dir/toolchain-*/bin/*g++)
(("${#compilers[@]}" > 0)) || { echo "Entware cross g++ not found" >&2; exit 1; }
cross_cxx="${compilers[0]}"
make -C "$SRC" -j"${TOOLBOX_JOBS:-4}" CXX="$cross_cxx" PLATFORM=linux ARCH=aarch64 GPU_SUPPORT=false QUIET=true
stage="$WORKSPACE/stage-btop"
mkdir -p "$stage/opt/bin" "$stage/opt/share/doc/btop"
binary="$(find "$SRC" -type f -name btop -perm /111 | head -n 1)"
[[ -n "$binary" ]] || { echo "btop output not found" >&2; exit 1; }
cp "$binary" "$stage/opt/bin/btop"
[[ ! -f "$SRC/LICENSE" ]] || cp "$SRC/LICENSE" "$stage/opt/share/doc/btop/LICENSE"
if [[ -d "$SRC/themes" ]]; then
  mkdir -p "$stage/opt/share/btop"
  cp -a "$SRC/themes" "$stage/opt/share/btop/"
fi
bash "$ROOT/scripts/check-router-elf.sh" "$stage/opt/bin/btop"
version="$(grep -m1 'Version =' "$SRC/src/btop.cpp" | cut -d'"' -f2)"
version="${version:-0.0.0}"
bash "$ROOT/scripts/ipk.sh" btop "$version-1" "$stage" "$OUT" "btop interactive system monitor"
