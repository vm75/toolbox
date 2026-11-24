#!/usr/bin/env bash
# Clean upstream -> optional single patch -> tool-specific build.
set -Eeuo pipefail
unset CDPATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() {
  echo "Usage: scripts/build.sh TOOL TARGET [UPSTREAM_REF]" >&2
  echo "Select targets from docs/architecture.md; use TOOLBOX_MUPDF_REF for Librera." >&2
  exit 2
}
[[ $# -ge 2 && $# -le 3 ]] || usage
TOOL="$1"; TARGET="$2"; REQUESTED_REF="${3:-}"
[[ "$TOOL" =~ ^[a-z0-9-]+$ && "$TARGET" =~ ^[a-z0-9-]+$ ]] || usage
# nginx uses signed nginx.org release tarballs rather than a Git checkout.
# Interpret its upstream ref as an exact X.Y.Z version, or blank for latest stable.
if [[ "$TOOL" == nginx && -n "$REQUESTED_REF" && ! "$REQUESTED_REF" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid nginx upstream ref: expected an exact X.Y.Z version" >&2
  exit 2
fi
export TOOLBOX_UPSTREAM_REF="$REQUESTED_REF"
[[ -r "$ROOT/tools/$TOOL/tool.conf" ]] || { echo "Unknown tool: $TOOL" >&2; exit 2; }
WORKSPACE="${TOOLBOX_WORKDIR:-$ROOT/.work}"
OUT="${TOOLBOX_OUTPUT:-$ROOT/dist}"
mkdir -p "$WORKSPACE/source" "$OUT"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
OUT="$(cd "$OUT" && pwd)"
: > "$OUT/build-info.txt"

config() {
  local name="$1"
  SOURCE_URL= SOURCE_REF= TARGETS= DEPS=
  # All manifests are repository-trusted shell fragments, never user input.
  source "$ROOT/tools/$name/tool.conf"
}
config "$TOOL"
[[ " $TARGETS " == *" $TARGET "* ]] || {
  echo "Unsupported target $TARGET for $TOOL; allowed: $TARGETS" >&2
  exit 2
}
declare -A PREPARED=() ACTIVE=()
prepare() {
  local name="$1" ref="$2" dep src patch sha d
  [[ -r "$ROOT/tools/$name/tool.conf" ]] || { echo "Missing dependency recipe $name" >&2; exit 1; }
  [[ -z "${ACTIVE[$name]:-}" ]] || { echo "Dependency cycle at $name" >&2; exit 1; }
  [[ -z "${PREPARED[$name]:-}" ]] || return 0
  ACTIVE[$name]=1
  config "$name"
  local url="$SOURCE_URL" default_ref="$SOURCE_REF" dependencies="$DEPS"
  for dep in $dependencies; do
    if [[ "$dep" == mupdf ]]; then
      prepare "$dep" "${TOOLBOX_MUPDF_REF:-}"
    else
      prepare "$dep" ""
    fi
  done
  src="$WORKSPACE/source/$name"
  if [[ -n "$url" ]]; then
    [[ ! -e "$src" ]] || { echo "Source directory must be fresh: $src" >&2; exit 1; }
    ref="${ref:-$default_ref}"
    if [[ "$ref" == latest-stable ]]; then
      local release_repo
      case "$name" in
        cryptomator) release_repo=cryptomator/android ;;
        librera) release_repo=foobnix/LibreraReader ;;
        *) echo "No latest-stable release resolver for $name" >&2; exit 1 ;;
      esac
      local auth_header=()
      local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
      if [[ -n "$token" ]]; then
        auth_header=(-H "Authorization: Bearer $token")
      fi
      local release_json=""
      release_json="$(curl -fsSL --retry 3 "${auth_header[@]}" \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: toolbox-build" \
        "https://api.github.com/repos/$release_repo/releases/latest" 2>/dev/null)" || true
      if [[ -n "$release_json" ]]; then
        ref="$(printf '%s\n' "$release_json" | python3 -c 'import json, sys
try:
    release = json.load(sys.stdin)
except Exception as e:
    sys.exit("Failed to parse GitHub release JSON: " + str(e))
tag = release.get("tag_name")
if release.get("draft") or release.get("prerelease") or not isinstance(tag, str) or not tag:
    sys.exit("No stable release tag returned by GitHub")
print("refs/tags/" + tag)')"
      else
        local latest_tag
        latest_tag="$(git ls-remote --tags --refs "$url" | cut -d/ -f3- | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V | tail -n 1)"
        if [[ -n "$latest_tag" ]]; then
          echo "::warning::GitHub release API unavailable; using highest numeric upstream tag for $name: $latest_tag" >&2
          ref="refs/tags/$latest_tag"
        else
          echo "Failed to resolve latest stable release for $name from GitHub API or git remote" >&2
          exit 1
        fi
      fi
    fi
    echo "::group::Fetch $name from $url at $ref"
    git init -q "$src"
    git -C "$src" remote add origin "$url"
    git -C "$src" -c protocol.version=2 fetch -q --depth 1 origin "$ref"
    git -C "$src" checkout -q --detach FETCH_HEAD
    sha="$(git -C "$src" rev-parse HEAD)"
    echo "$name upstream $sha ($ref)"
    if [[ "$name" == "$TOOL" && ( "$name" == cryptomator || "$name" == librera ) ]]; then
      # Use the selected tag/ref, never Gradle's version or the workflow run ID.
      local version="${ref#refs/tags/}"
      version="${version#refs/heads/}"
      export APK_VERSION="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._-' '-')"
      [[ -n "$APK_VERSION" ]] || { echo "Empty APK version" >&2; exit 1; }
    fi
    patch="$ROOT/tools/$name/custom.patch"
    if [[ -s "$patch" ]]; then
      echo "Checking $patch"
      if ! git -C "$src" apply --check "$patch"; then
        echo "::error::Patch rejected for $name at $sha. Update tools/$name/custom.patch; no binary published." >&2
        exit 1
      fi
      git -C "$src" apply --index "$patch"
      echo "$name patch_sha256 $(sha256sum "$patch" | cut -d' ' -f1)" >> "$OUT/build-info.txt"
    fi
    # Resolve submodules AFTER custom .gitmodules and gitlink changes.
    if [[ -f "$src/.gitmodules" ]]; then
      git -C "$src" submodule sync --recursive
      git -C "$src" submodule update --init --recursive
    fi
    echo "$name upstream_commit $sha" >> "$OUT/build-info.txt"
    echo "$name source_ref $ref" >> "$OUT/build-info.txt"
    echo "::endgroup::"
  else
    mkdir -p "$src"
  fi
  PREPARED[$name]=1
  unset 'ACTIVE[$name]'
}
prepare "$TOOL" "$REQUESTED_REF"
if [[ "${TOOLBOX_PREPARE_ONLY:-0}" == 1 ]]; then
  echo "Source preparation successful. No build requested."
  exit 0
fi
config "$TOOL"
export ROOT WORKSPACE OUT TARGET TOOL
export SRC="$WORKSPACE/source/$TOOL"
echo "tool $TOOL" >> "$OUT/build-info.txt"
echo "target $TARGET" >> "$OUT/build-info.txt"
bash "$ROOT/tools/$TOOL/build.sh"
bash "$ROOT/scripts/release-version.sh"
find "$OUT" -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 -r sha256sum > "$OUT/SHA256SUMS"
[[ "$(find "$OUT" -type f ! -name build-info.txt ! -name SHA256SUMS | wc -l)" -gt 0 ]] || {
  echo "::error::No build artifact produced" >&2; exit 1;
}
echo "Build complete: $OUT"
