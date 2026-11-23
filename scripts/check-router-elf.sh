#!/usr/bin/env bash
# Validate Entware AArch64 or soft-float ARMv7 ELF and the glibc 2.27 ceiling.
set -Eeuo pipefail
[[ $# == 1 ]] || { echo "Usage: check-router-elf.sh BINARY (TARGET=entware-...)" >&2; exit 2; }
binary="$1"
case "${TARGET:-}" in
  entware-aarch64) machine='AArch64'; loader=/opt/lib/ld-linux-aarch64.so.1 ;;
  entware-armv7) machine='ARM'; loader=/opt/lib/ld-linux.so.3 ;;
  *) echo "Unsupported Entware ELF target: ${TARGET:-unset}" >&2; exit 2 ;;
esac
readelf -h "$binary" | grep -Eq "Machine: *$machine([[:space:]]|$)" || {
  echo "Wrong ELF machine (expected $machine): $binary" >&2; exit 1;
}
# Entware armv7sf-k3.2 uses the soft-float ABI.
if [[ "${TARGET}" == entware-armv7 ]] && readelf -A "$binary" | grep -q 'Tag_ABI_VFP_args: VFP registers'; then
  echo "ARMv7 hard-float ABI incompatible with Entware armv7sf" >&2; exit 1
fi
interpreter="$(readelf -l "$binary" | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p')"
case "$interpreter" in
  '' ) ;;  # Static binaries, including musl, need no /opt loader.
  "$loader" ) ;;
  *) echo "Unsupported Entware dynamic loader: $interpreter (expected $loader)" >&2; exit 1 ;;
esac
while read -r version; do
  major="${version%%.*}"; minor="${version#*.}"
  if (( major > 2 || (major == 2 && minor > 27) )); then
    echo "Requires GLIBC_$version beyond Entware GLIBC_2.27" >&2; exit 1
  fi
done < <(readelf --version-info "$binary" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -Vu || true)
echo "Entware $TARGET ELF checks passed: $binary"
