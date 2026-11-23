#!/usr/bin/env bash
# Install a SHA-256-pinned, prebuilt musl C++ cross compiler for static btop.
set -Eeuo pipefail
[[ $# == 2 ]] || { echo "Usage: install-musl-toolchain.sh TRIPLE SHA256" >&2; exit 2; }
triple="$1" expected="$2"
case "$triple" in
  aarch64-unknown-linux-musl|armv7-unknown-linux-musleabi) ;;
  *) echo "Unsupported musl target: $triple" >&2; exit 2 ;;
esac
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || exit 2
url="https://github.com/cross-tools/musl-cross/releases/download/20250929/$triple.tar.xz"
archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT
curl --fail --location --retry 3 "$url" --output "$archive"
printf '%s  %s\n' "$expected" "$archive" | sha256sum --check --status
mkdir -p /opt/x-tools
tar -xJf "$archive" -C /opt/x-tools
compiler="/opt/x-tools/$triple/bin/$triple-g++"
[[ -x "$compiler" ]] || { echo "Missing expected compiler $compiler" >&2; exit 1; }
[[ "$("$compiler" -dumpfullversion -dumpversion)" == 15.2.0 ]] || {
  echo "Expected GCC 15.2.0 in downloaded archive" >&2; exit 1;
}
"$compiler" --version | head -n 1
