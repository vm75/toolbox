#!/usr/bin/env bash
set -Eeuo pipefail
# Static musl GCC 15.2 for modern C++23 btop; glibc Entware GCC 8.4 is too old.
case "$TARGET" in
  entware-aarch64) triple=aarch64-unknown-linux-musl; arch=aarch64 ;;
  entware-armv7) triple=armv7-unknown-linux-musleabi; arch=armv7 ;;
  *) echo "Unsupported btop target: $TARGET" >&2; exit 2 ;;
esac
cxx="${TOOLBOX_MUSL_PREFIX:-/opt/x-tools}/$triple/bin/$triple-g++"
[[ -x "$cxx" ]] || { echo "Missing GCC 15.2 musl cross-compiler: $cxx" >&2; exit 1; }
version="$("$cxx" -dumpfullversion -dumpversion)"
[[ "$version" == 15.2.0 ]] || { echo "Expected musl GCC 15.2.0, got $version" >&2; exit 1; }
echo "Building btop for $TARGET with $cxx ($version)"
make -C "$SRC" -j"${TOOLBOX_JOBS:-4}" CXX="$cxx" \
  PLATFORM=linux ARCH="$arch" STATIC=true GPU_SUPPORT=false RSMI_STATIC= QUIET=true

binary="$SRC/bin/btop"
[[ -s "$binary" ]] || { echo "btop output not found: $binary" >&2; exit 1; }
# A static musl binary must not require an installed loader or shared runtime.
if readelf -l "$binary" | grep -q ' INTERP '; then
  echo "btop is not static: an ELF interpreter is present" >&2; exit 1
fi
if readelf -d "$binary" 2>/dev/null | grep -q '(NEEDED)'; then
  echo "btop is not static: shared libraries are required" >&2; exit 1
fi
bash "$ROOT/scripts/check-router-elf.sh" "$binary"

stage="$WORKSPACE/stage-btop"
mkdir -p "$stage/opt/bin" "$stage/opt/share/doc/btop"
cp "$binary" "$stage/opt/bin/btop"
[[ ! -f "$SRC/LICENSE" ]] || cp "$SRC/LICENSE" "$stage/opt/share/doc/btop/LICENSE"
if [[ -d "$SRC/themes" ]]; then
  mkdir -p "$stage/opt/share/btop"
  cp -a "$SRC/themes" "$stage/opt/share/btop/"
fi
version="$(grep -m1 'Version =' "$SRC/src/btop.cpp" | cut -d'"' -f2)"
version="${version:-0.0.0}"
bash "$ROOT/scripts/ipk.sh" btop "$version-1" "$stage" "$OUT" "btop interactive system monitor"
