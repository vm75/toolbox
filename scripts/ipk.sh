#!/usr/bin/env bash
# Minimal opkg-compatible gzip/tar IPK. Router staging always starts under /opt.
set -Eeuo pipefail
[[ $# -ge 5 && $# -le 6 ]] || { echo "Usage: ipk.sh NAME VERSION STAGE OUT DESCRIPTION [DEPENDS]" >&2; exit 2; }
name="$1"; version="$2"; stage="$3"; out="$4"; desc="$5"; depends="${6:-}"
[[ "$name" =~ ^[a-z0-9][a-z0-9+.-]*$ && "$version" =~ ^[a-zA-Z0-9.+:~-]+$ ]] || exit 2
[[ -d "$stage/opt" ]] || { echo "Missing /opt payload for $name" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/control" "$out"
{
  printf 'Package: %s\nVersion: %s\nArchitecture: aarch64-3.10\nMaintainer: toolbox <https://github.com/vm75/toolbox>\nSection: utils\nPriority: optional\nDescription: %s\n' "$name" "$version" "$desc"
  [[ -z "$depends" ]] || printf 'Depends: %s\n' "$depends"
} > "$tmp/control/control"
printf '2.0\n' > "$tmp/debian-binary"
tar -C "$tmp/control" -czf "$tmp/control.tar.gz" .
tar -C "$stage" -czf "$tmp/data.tar.gz" .
tar -C "$tmp" -czf "$out/${name}_${version}_aarch64-3.10.ipk" debian-binary control.tar.gz data.tar.gz
tar -tzf "$out/${name}_${version}_aarch64-3.10.ipk" | grep -q 'control.tar.gz'
