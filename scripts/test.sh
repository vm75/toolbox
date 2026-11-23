#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
for script in scripts/*.sh tools/*/build.sh tools/nginx/upstream-builder.sh; do
  bash -n "$script"
done
for conf in tools/*/tool.conf; do
  [[ -r "$conf" ]] || exit 1
  SOURCE_URL= SOURCE_REF= TARGETS= DEPS=
  source "$conf"
  [[ -n "$TARGETS" && -r "${conf%tool.conf}build.sh" ]] || {
    echo "Invalid tool recipe: $conf" >&2; exit 1;
  }
done
for workflow in .github/workflows/*.yml; do
  grep -q '^  workflow_dispatch:' "$workflow" || {
    echo "Manual dispatch missing: $workflow" >&2; exit 1;
  }
  if grep -Eq '^  (push|pull_request|schedule|release|workflow_run):' "$workflow"; then
    echo "Forbidden automatic trigger: $workflow" >&2; exit 1;
  fi
done
# Exactly one patch per project, where needed.
for dir in tools/*; do
  [[ ! -d "$dir/patches" ]] || {
    echo "Legacy multi-patch directory exists: $dir/patches" >&2; exit 1;
  }
done
echo "Toolbox structural checks passed"
