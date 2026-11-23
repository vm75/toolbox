#!/usr/bin/env bash
set -Eeuo pipefail
# The Maestro-derived builder verifies upstream release signatures and packages nginx modules.
args=(--channel stable --jobs "${TOOLBOX_JOBS:-4}" --workdir "${TOOLBOX_NGINX_CACHE:-$WORKSPACE/nginx-cache}" --output "$OUT/nginx")
if [[ -n "${TOOLBOX_NGINX_VERSION:-}" ]]; then
  args=(--version "$TOOLBOX_NGINX_VERSION" --jobs "${TOOLBOX_JOBS:-4}" --workdir "${TOOLBOX_NGINX_CACHE:-$WORKSPACE/nginx-cache}" --output "$OUT/nginx")
fi
bash "$ROOT/tools/nginx/upstream-builder.sh" "${args[@]}"
shopt -s nullglob
packages=("$OUT/nginx/"*.ipk)
(("${#packages[@]}" >= 4)) || { echo "Expected nginx and module IPKs" >&2; exit 1; }
