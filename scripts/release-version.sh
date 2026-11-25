#!/usr/bin/env bash
# Record the version of the primary deliverable, not a dependency or run ID.
set -Eeuo pipefail
: "${TOOL:?}" "${TARGET:?}" "${OUT:?}" "${SRC:?}"
version=
if [[ "$TARGET" == entware-* ]]; then
  package="$TOOL"
  [[ "$TOOL" != nginx ]] || package=nginx-ssl
  mapfile -d '' -t packages < <(find "$OUT" -type f -name "$package"'_*.ipk' -print0)
  (( ${#packages[@]} == 1 )) || { echo "Expected exactly one primary $package IPK" >&2; exit 1; }
  filename="${packages[0]##*/}"
  arch=aarch64-3.10
  [[ "$TARGET" != entware-armv7 ]] || arch=armv7-3.2
  [[ "$filename" == "$package"_*_"$arch".ipk ]] || exit 1
  version="${filename#"$package"_}"
  version="${version%_"$arch".ipk}"
elif [[ "$TOOL" == vaultwarden ]]; then
  # Use the actual Linux deliverable, just as the Entware path uses its IPK.
  mapfile -d '' -t archives < <(find "$OUT" -type f -name "vaultwarden-*-$TARGET.tgz" -print0)
  (( ${#archives[@]} == 1 )) || { echo "Expected exactly one Vaultwarden archive" >&2; exit 1; }
  filename="${archives[0]##*/}"
  version="${filename#vaultwarden-}"
  version="${version%-$TARGET.tgz}"
else
  # The checkout is shallow; an explicit tag may not have a local tag ref.
  sha="$(git -C "$SRC" rev-parse --short=12 HEAD)"
  ref="$(sed -n "s/^$TOOL source_ref //p" "$OUT/build-info.txt")"
  tag=
  if [[ "$ref" == refs/tags/* ]]; then
    tag="${ref#refs/tags/}"
  elif [[ -n "$ref" && "$ref" != refs/heads/* ]]; then
    # Match the actual fetched commit, including peeled annotated tags.
    full_sha="$(git -C "$SRC" rev-parse HEAD)"
    remote_tags="$(git -C "$SRC" ls-remote --tags origin "refs/tags/$ref" "refs/tags/$ref^{}" 2>/dev/null)" || remote_tags=
    if grep -Fq "$full_sha"$'\t' <<< "$remote_tags"; then tag="$ref"; fi
  fi
  if [[ "$TOOL" == cryptomator || "$TOOL" == librera ]]; then
    version="${APK_VERSION:?missing APK version}"
    [[ -n "$tag" ]] || version="$version-g$sha"
  elif [[ -n "$tag" ]]; then
    version="$tag"
  else
    # Branch builds may report the same source version for many commits.
    case "$TOOL" in
      busybox)
        version="$(awk -F ' *= *' '
          $1=="VERSION" {v=$2} $1=="PATCHLEVEL" {p=$2} $1=="SUBLEVEL" {s=$2}
          END {if(v!="" && p!="" && s!="") print v "." p "." s}
        ' "$SRC/Makefile")" ;;
      john)
        version="$("$SRC/run/john" --list=build-info 2>/dev/null | sed -nE 's/^Version: ([^[:space:]]+).*/\1/p' | head -n 1)" || version= ;;
      mupdf)
        version="$(sed -nE 's/^#define FZ_VERSION "([^"]+)".*/\1/p' "$SRC/include/mupdf/fitz/version.h")" ;;
      wireguard)
        version="$(sed -nE 's/^const Version = "([^"]+)".*/\1/p' "$SRC/version.go")" ;;
      wg-util)
        version="$(git -C "$SRC" tag --points-at HEAD | sort -V | tail -n 1)" ;;
    esac
    if [[ -n "$version" ]]; then version="$version-g$sha"; else version="g$sha"; fi
  fi
fi
# Git ref/file-safe version. Preserve ordinary upstream versions verbatim.
version="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._+-' '-' | sed -E 's/\.{2,}/-/g; s/^\.+//; s/\.+$//')"
[[ -n "$version" ]] || { echo "Empty release version" >&2; exit 1; }
printf 'release_version %s\n' "$version" >> "$OUT/build-info.txt"
