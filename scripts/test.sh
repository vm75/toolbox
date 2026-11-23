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
# The three manually published GHCR builders: two Entware targets and Android.
[[ -f images/entware-aarch64/Dockerfile && -f images/entware-armv7/Dockerfile && -f images/android/Dockerfile ]] || {
  echo "Missing reusable builder Dockerfile" >&2; exit 1;
}
[[ -f scripts/run.sh ]] || { echo "Missing builder selection runner" >&2; exit 1; }
[[ ! -e .github/workflows/toolchain-image.yml && ! -e tools/nginx/Dockerfile ]] || {
  echo "Legacy single-purpose image workflow or Dockerfile still present" >&2; exit 1;
}
[[ ! -d tools/keys && ! -d tools/launcher ]] || {
  echo "Unsupported local-only helpers or key folder still present" >&2; exit 1;
}
grep -q '^run-name:' .github/workflows/build.yml || {
  echo "Workflow run names must display the selected tool and target" >&2; exit 1;
}
[[ ! -d tools/rsync ]] && ! grep -Fq 'rsync' .github/workflows/build.yml || {
  echo "Removed rsync recipe must not appear in the workflow" >&2; exit 1;
}
# GitHub Actions cannot make one dropdown depend on another. Check that
# the combined dropdown lists exactly the tool.conf-supported combinations.
declare -A workflow_choices=()
while IFS= read -r selection; do
  [[ "$selection" == *' / '* ]] || { echo "Invalid dropdown choice: $selection" >&2; exit 1; }
  name="${selection%% / *}"
  target="${selection#* / }"
  if [[ "$name" == 'John the Ripper' ]]; then name=john; fi
  [[ "$name" =~ ^[a-z0-9-]+$ && "$target" =~ ^[a-z0-9-]+$ ]] || exit 1
  [[ -f "tools/$name/tool.conf" ]] || { echo "Unknown dropdown tool: $name" >&2; exit 1; }
  TARGETS=
  source "tools/$name/tool.conf"
  [[ " $TARGETS " == *" $target "* ]] || {
    echo "Invalid tool/target choice: $selection" >&2; exit 1;
  }
  [[ -z "${workflow_choices["$name/$target"]+set}" ]] || {
    echo "Duplicate tool/target choice: $selection" >&2; exit 1;
  }
  workflow_choices["$name/$target"]=1
done < <(sed -n '/^      build:/,/^      upstream_ref:/s/^          - //p' .github/workflows/build.yml)
[[ ${#workflow_choices[@]} -gt 0 ]] || { echo "Missing tool/target dropdown choices" >&2; exit 1; }
for conf in tools/*/tool.conf; do
  name="${conf#tools/}"
  name="${name%/tool.conf}"
  TARGETS=
  source "$conf"
  for target in $TARGETS; do
    [[ -n "${workflow_choices["$name/$target"]+set}" ]] || {
      echo "Missing tool/target choice: $name/$target" >&2; exit 1;
    }
  done
done
grep -Fq 'tool=john' .github/workflows/build.yml || {
  echo "John the Ripper must map to the internal john recipe" >&2; exit 1;
}
# The user-facing build form has only one upstream ref and no image tag override.
! grep -Eq 'nginx_version|builder_image_tag|TOOLBOX_NGINX_VERSION|TOOLBOX_BUILDER_TAG' \
    .github/workflows/build.yml scripts/run.sh tools/nginx/build.sh || {
  echo "Redundant nginx release or builder tag override remains" >&2; exit 1;
}
grep -Fq 'export TOOLBOX_UPSTREAM_REF="$REQUESTED_REF"' scripts/build.sh &&
  grep -Fq -- '--version "$TOOLBOX_UPSTREAM_REF"' tools/nginx/build.sh || {
  echo "Nginx release must be selected via the upstream ref" >&2; exit 1;
}
# Build jobs may use signing secrets, but must not appear as deployments.
grep -Fq 'deployment: false' .github/workflows/build.yml || {
  echo "Tool builds must not create GitHub Deployments" >&2; exit 1;
}
grep -Fq "'android-signing' || 'build'" .github/workflows/build.yml || {
  echo "Android signing environment routing must be preserved" >&2; exit 1;
}
old_target="router""-aarch64"
! grep -R -l -F "$old_target" scripts tools .github/workflows README.md docs || {
  echo "Legacy Entware target label still referenced" >&2; exit 1;
}
# Smoke-test the opkg Architecture field for both Entware targets without building binaries.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# nginx is not a Git checkout: validate the shared ref as X.Y.Z even when
# prepare_only avoids downloading source or building packages.
TOOLBOX_PREPARE_ONLY=1 TOOLBOX_WORKDIR="$tmp/nginx-prepare" \
  TOOLBOX_OUTPUT="$tmp/nginx-prepare-out" \
  bash scripts/build.sh nginx entware-aarch64 1.28.0 >/dev/null
if TOOLBOX_PREPARE_ONLY=1 TOOLBOX_WORKDIR="$tmp/nginx-invalid" \
   TOOLBOX_OUTPUT="$tmp/nginx-invalid-out" \
   bash scripts/build.sh nginx entware-aarch64 not-a-release >/dev/null 2>&1; then
  echo "Invalid nginx upstream version was accepted" >&2; exit 1
fi
# Mock the expensive Entware package builder and check both version routes.
mkdir -p "$tmp/mock-root/tools/nginx" "$tmp/mock-root/scripts" "$tmp/mock-out"
cat > "$tmp/mock-root/tools/nginx/upstream-builder.sh" <<'MOCK_NGINX'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" > "$TOOLBOX_TEST_NGINX_ARGS"
out=
while (( $# )); do
  if [[ "$1" == --output ]]; then out="$2"; shift 2; else shift; fi
done
mkdir -p "$out"
touch "$out"/{nginx-ssl,nginx-mod-brotli,nginx-mod-stream,nginx-mod-headers-more}.ipk
MOCK_NGINX
printf 'exit 0\n' > "$tmp/mock-root/scripts/check-router-elf.sh"
for ref in '' '1.28.0'; do
  ROOT="$tmp/mock-root" WORKSPACE="$tmp/mock-work" OUT="$tmp/mock-out" \
    TARGET=entware-aarch64 TOOLBOX_UPSTREAM_REF="$ref" \
    TOOLBOX_TEST_NGINX_ARGS="$tmp/nginx-args" \
    bash tools/nginx/build.sh
  if [[ -n "$ref" ]]; then
    grep -Fqx -- '--version' "$tmp/nginx-args" &&
      grep -Fqx -- "$ref" "$tmp/nginx-args" || {
      echo "Nginx did not receive the exact upstream release" >&2; exit 1;
    }
  else
    grep -Fqx -- '--channel' "$tmp/nginx-args" &&
      grep -Fqx -- 'stable' "$tmp/nginx-args" || {
      echo "Nginx default did not select the stable channel" >&2; exit 1;
    }
  fi
done
mkdir -p "$tmp/stage/opt/bin"
printf 'smoke-test\n' > "$tmp/stage/opt/bin/example"
for target in entware-aarch64 entware-armv7; do
  case "$target" in
    entware-aarch64) arch=aarch64-3.10 ;;
    entware-armv7) arch=armv7-3.2 ;;
  esac
  TARGET="$target" bash scripts/ipk.sh sample 0.0.0-1 "$tmp/stage" "$tmp/out" "Smoke-test package"
  package="$tmp/out/sample_0.0.0-1_$arch.ipk"
  [[ -s "$package" ]] || { echo "Missing $arch test IPK" >&2; exit 1; }
  tar -xOf "$package" control.tar.gz | tar -xzOf - ./control | grep -qx "Architecture: $arch" || {
    echo "Wrong opkg Architecture for $target" >&2; exit 1;
  }
done
# All three tools must advertise the supported Entware ARMv7 *soft-float* target.
for tool in nginx vaultwarden btop; do
  TARGETS=
  source "tools/$tool/tool.conf"
  [[ " $TARGETS " == *" entware-armv7 "* ]] || {
    echo "$tool is missing Entware ARMv7 support" >&2; exit 1;
  }
done
grep -Fq -- '--target armv7-3.2' images/entware-armv7/Dockerfile || {
  echo "ARMv7 builder must use its own Entware buildroot configuration" >&2; exit 1;
}
grep -Fq 'arm-unknown-linux-gnueabi' tools/vaultwarden/build.sh || {
  echo "Vaultwarden ARMv7 must use the Linux 3.2-compatible GNU soft-float Rust target" >&2; exit 1;
}
grep -Fq 'rustup target add "$rust_target"' tools/vaultwarden/build.sh || {
  echo "Vaultwarden must install rust-std after selecting upstream rust-toolchain.toml" >&2; exit 1;
}
grep -Fq 'STATIC=true GPU_SUPPORT=false' tools/btop/build.sh || {
  echo "Entware btop must be statically linked" >&2; exit 1;
}
# Route smoke tests: stub docker so ARMv7 cannot accidentally ask for an Android
# signing key or rebuild the Entware toolchain from scratch.
mkdir -p "$tmp/fake-bin"
cat > "$tmp/fake-bin/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TOOLBOX_TEST_DOCKER_CALLS"
FAKE_DOCKER
chmod +x "$tmp/fake-bin/docker"
for target in entware-aarch64 entware-armv7; do
  case "$target" in
    entware-aarch64) builder=entware-aarch64; tag=v3 ;;
    entware-armv7) builder=entware-armv7; tag=v2 ;;
  esac
  for tool in nginx btop; do
    : > "$tmp/docker-calls"
    GITHUB_REPOSITORY=vm75/toolbox TOOLBOX_TEST_DOCKER_CALLS="$tmp/docker-calls" \
      PATH="$tmp/fake-bin:$PATH" bash scripts/run.sh "$tool" "$target" >/dev/null
    grep -Fqx "pull ghcr.io/vm75/toolbox/$builder:$tag" "$tmp/docker-calls" || {
      echo "Wrong builder image for $tool/$target" >&2; exit 1;
    }
    grep -Fq -- '--env TOOLBOX_NGINX_CACHE=/opt/nginx-entware' "$tmp/docker-calls" || {
      echo "Missing prebuilt Entware nginx toolchain cache for $tool/$target" >&2; exit 1;
    }
    grep -Fq "bash scripts/build.sh $tool $target" "$tmp/docker-calls" || {
      echo "Wrong build command for $tool/$target" >&2; exit 1;
    }
    ! grep -Fq 'ANDROID_KEYSTORE_FILE' "$tmp/docker-calls" || {
      echo "Router build incorrectly requested Android signing for $tool/$target" >&2; exit 1;
    }
  done
done
echo "Toolbox structural checks passed"
