#!/usr/bin/env bash
set -Eeuo pipefail
# The in-tree builder verifies upstream release signatures and packages nginx modules.
case "$TARGET" in
  entware-aarch64) entware_target=aarch64-3.10 ;;
  entware-armv7) entware_target=armv7-3.2 ;;
  *) echo "Unsupported nginx target: $TARGET" >&2; exit 2 ;;
esac
args=(--no-update --target "$entware_target" --channel stable --jobs "${TOOLBOX_JOBS:-4}" --workdir "${TOOLBOX_NGINX_CACHE:-$WORKSPACE/nginx-cache}" --output "$OUT/nginx")
# The normal upstream-ref field selects an exact nginx.org release when set.
if [[ -n "${TOOLBOX_UPSTREAM_REF:-}" ]]; then
  args=(--no-update --target "$entware_target" --version "$TOOLBOX_UPSTREAM_REF" --jobs "${TOOLBOX_JOBS:-4}" --workdir "${TOOLBOX_NGINX_CACHE:-$WORKSPACE/nginx-cache}" --output "$OUT/nginx")
fi
bash "$ROOT/tools/nginx/upstream-builder.sh" "${args[@]}"
shopt -s nullglob
packages=("$OUT/nginx/"*.ipk)
(("${#packages[@]}" >= 4)) || { echo "Expected nginx and module IPKs" >&2; exit 1; }

# Check the actual executable and modules against the selected Entware ABI.
bash "$ROOT/scripts/check-router-elf.sh" "$OUT/nginx/nginx"
for binary in "$OUT/nginx/"*.so; do
  [[ ! -f "$binary" ]] || bash "$ROOT/scripts/check-router-elf.sh" "$binary"
done
