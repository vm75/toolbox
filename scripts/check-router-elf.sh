#!/usr/bin/env bash
# Verify target and reject binaries requiring a newer glibc or non-Entware loader.
set -Eeuo pipefail
[[ $# -eq 1 ]] || exit 2
binary="$1"
readelf -h "$binary" | grep -Eq 'Machine: *AArch64' || {
  echo "Not an AArch64 ELF: $binary" >&2; exit 1;
}
interpreter="$(readelf -l "$binary" | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p')"
case "$interpreter" in
  ''|/opt/lib/ld-linux-aarch64.so.1) ;;
  *) echo "Unsupported router dynamic loader: $interpreter" >&2; exit 1 ;;
esac
while read -r version; do
  major="${version%%.*}"; minor="${version#*.}"
  if (( major > 2 || (major == 2 && minor > 27) )); then
    echo "Requires GLIBC_$version, beyond router GLIBC_2.27" >&2
    exit 1
  fi
done < <(readelf --version-info "$binary" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -Vu || true)
echo "AArch64 ELF compatibility checks passed: $binary"
