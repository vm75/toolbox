#!/usr/bin/env bash
# Publish a versioned tag at the exact source commit, never move an existing tag.
set -Eeuo pipefail
: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${RUNNER_TEMP:?}"
: "${SELECTED_TOOL:?}" "${SELECTED_TARGET:?}" "${SOURCE_BRANCH:?}"
tool="$SELECTED_TOOL" target="$SELECTED_TARGET"
[[ "$tool" =~ ^[a-z0-9-]+$ && "$target" =~ ^[a-z0-9-]+$ ]] || exit 2
api="repos/$GITHUB_REPOSITORY"
[[ "$SOURCE_BRANCH" == "toolbox-builds/r$GITHUB_RUN_ID-a"* ]] || exit 2
actual="$(gh api "$api/git/ref/heads/$SOURCE_BRANCH" --jq .object.sha)"
[[ "$actual" == "$GITHUB_SHA" ]] || { echo "Source reservation no longer points to build commit" >&2; exit 1; }
info=dist/build-info.txt
grep -Fxq "tool $tool" "$info"
grep -Fxq "target $target" "$info"
mapfile -t versions < <(sed -n 's/^release_version //p' "$info")
(( ${#versions[@]} == 1 )) || { echo "Missing or ambiguous release version" >&2; exit 1; }
version="${versions[0]}"
[[ "$version" =~ ^[A-Za-z0-9._+-]+$ ]] || exit 1
platform="${target%-*}" arch="${target##*-}"
base="toolbox-$tool-$platform-${version}_$arch"
git check-ref-format "refs/tags/$base"
# Source/patch/dependency identity, including the exact toolbox recipe commit.
# Ignore how an identical upstream commit was selected (branch vs tag).
identity="$(
  {
    printf 'toolbox_commit %s\n' "$GITHUB_SHA"
    grep -v ' source_ref ' "$info"
    if [[ "$tool" == nginx ]]; then
      grep -E '^(nginx_source_sha256|entware_commit|entware_packages_commit)=' dist/nginx/build-info.txt
    fi
  } | sha256sum | cut -d' ' -f1
)"
marker="Build identity: $identity"
# Distinguish missing refs/releases from authentication or service failures.
lookup() {
  local output
  if output="$(gh api "$1" 2>"$RUNNER_TEMP/toolbox-api-error")"; then
    printf '%s\n' "$output"
  elif grep -Fq 'HTTP 404' "$RUNNER_TEMP/toolbox-api-error"; then
    return 1
  else
    cat "$RUNNER_TEMP/toolbox-api-error" >&2
    return 2
  fi
}
cleanup() {
  # Keep the source anchor on failure so a release-only rerun can recover.
  gh api --method DELETE "$api/git/refs/heads/$SOURCE_BRANCH" --silent ||
    echo "::warning::Could not remove temporary source branch $SOURCE_BRANCH" >&2
}
# Validate deliverables before creating a public tag. Flat release asset names.
case "$target:$tool" in
  entware-aarch64:*|entware-armv7:*)
    mapfile -d '' -t assets < <(find dist -type f -name '*.ipk' -print0 | sort -z)
    (( ${#assets[@]} > 0 )) || { echo "No IPKs found" >&2; exit 1; }
    if [[ "$tool" == nginx ]]; then
      cp dist/nginx/build-info.txt "$RUNNER_TEMP/nginx-build-info.txt"
      assets+=("$RUNNER_TEMP/nginx-build-info.txt")
    fi
    assets+=("$info")
    ;;
  android-arm64:cryptomator|android-arm64:librera)
    mapfile -d '' -t assets < <(find dist -type f -name '*.apk' -print0 | sort -z)
    (( ${#assets[@]} > 0 )) || { echo "No APKs found" >&2; exit 1; }
    assets+=("$info")
    ;;
  *) assets=() ;;
esac
if (( ${#assets[@]} )); then
  for asset in "${assets[@]}"; do
    (cd "$(dirname "$asset")" && sha256sum -- "$(basename "$asset")")
  done > "$RUNNER_TEMP/SHA256SUMS"
  assets+=("$RUNNER_TEMP/SHA256SUMS")
fi
# Atomic ref creation prevents overwrites even when two builds finish together.
# A tag without a complete matching release is left intact and not reused.
for ((revision=1; revision<=1000; revision++)); do
  tag="$base"
  (( revision == 1 )) || tag="$base-r$revision"
  if existing="$(lookup "$api/releases/tags/$tag")"; then
    if jq -e --arg marker "$marker" '(.draft == false) and (.body // "" | split("\n") | index($marker) != null)' <<< "$existing" >/dev/null; then
      actual="$(gh api "$api/git/ref/tags/$tag" --jq .object.sha)"
      [[ "$actual" == "$GITHUB_SHA" ]] || { echo "Matching release has unexpected tag commit" >&2; exit 1; }
      echo "Reusing existing release $tag (same build identity)"
      cleanup
      exit 0
    fi
    continue
  else
    [[ $? == 1 ]] || exit 1
  fi
  if lookup "$api/git/ref/tags/$tag" >/dev/null; then
    continue
  else
    [[ $? == 1 ]] || exit 1
  fi
  if gh api --method POST "$api/git/refs" -f "ref=refs/tags/$tag" -f "sha=$GITHUB_SHA" --silent; then
    break
  fi
  # A competing build may have just claimed this name. Never force-update.
  if lookup "$api/git/ref/tags/$tag" >/dev/null; then continue; fi
  echo "Unable to create release tag $tag at $GITHUB_SHA" >&2
  exit 1
done
(( revision <= 1000 )) || { echo "No free release revision" >&2; exit 1; }
actual="$(gh api "$api/git/ref/tags/$tag" --jq .object.sha)"
[[ "$actual" == "$GITHUB_SHA" ]] || exit 1
if (( ${#assets[@]} == 0 )); then
  tar -C dist -czf "$RUNNER_TEMP/$tag.tar.gz" .
  assets=("$RUNNER_TEMP/$tag.tar.gz")
fi
{
  printf 'Requested upstream build. Validate on target before deploying.\n\n'
  printf 'Version: %s\nToolbox commit: %s\n%s\n' "$version" "$GITHUB_SHA" "$marker"
  printf 'Workflow run: %s/%s/actions/runs/%s (attempt %s)\n\n' "${GITHUB_SERVER_URL:-https://github.com}" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT"
  printf 'Source and patch metadata:\n'
  printf '\x60\x60\x60text\n'
  cat "$info"
  printf '\x60\x60\x60\n'
} > "$RUNNER_TEMP/release-notes.md"
gh release create "$tag" "${assets[@]}" --repo "$GITHUB_REPOSITORY" \
  --title "$tag" --notes-file "$RUNNER_TEMP/release-notes.md" --latest=false --verify-tag
cleanup
