#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
for script in scripts/*.sh tools/*/build.sh tools/nginx/upstream-builder.sh; do
  bash -n "$script"
done
for conf in tools/*/tool.conf; do
  SOURCE_URL= SOURCE_REF= TARGETS= DEPS=
  source "$conf"
  [[ -n "$TARGETS" && -r "${conf%tool.conf}build.sh" ]] || {
    echo "Invalid tool recipe: $conf" >&2; exit 1;
  }
  for dep in $DEPS; do
    [[ -r "tools/$dep/tool.conf" ]] || { echo "Missing dependency $dep" >&2; exit 1; }
  done
done
for workflow in .github/workflows/*.yml; do
  awk '
    /^on:/ { in_on=1; next }
    in_on && /^[^[:space:]]/ { in_on=0 }
    in_on && /^  workflow_dispatch:/ { manual=1 }
    in_on && /^  (push|pull_request|schedule|release|workflow_run):/ { automatic=1 }
    END { if (!manual || automatic) exit 1 }
  ' "$workflow" || { echo "Not manual-only: $workflow" >&2; exit 1; }
done
for dir in tools/*; do
  [[ ! -d "$dir/patches" ]] || {
    echo "Legacy multi-patch directory exists: $dir/patches" >&2; exit 1;
  }
done
# The only custom environments are the manually published Entware and Android images.
[[ -f images/entware-aarch64/Dockerfile && -f images/android/Dockerfile ]] || {
  echo "Missing reusable builder Dockerfile" >&2; exit 1;
}
[[ -f scripts/run.sh ]] || { echo "Missing builder selection runner" >&2; exit 1; }
[[ ! -e .github/workflows/toolchain-image.yml && ! -e tools/nginx/Dockerfile ]] || {
  echo "Legacy single-purpose image workflow or Dockerfile still present" >&2; exit 1;
}
echo "Toolbox structural checks passed"
