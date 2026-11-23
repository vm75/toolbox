# Architecture

```text
manual workflow_dispatch (tool + compatible target + optional refs)
       |
  scripts/run.sh -> choose existing GHCR builder or GitHub Ubuntu runner
       |
  scripts/build.sh
       |
  tool.conf -> prepare dependencies recursively -> fresh upstream fetch
       |                (librera -> mupdf)
  git apply --check custom.patch, then git apply --index (if present)
       |
  initialize submodules pinned by patched sources
       |
  per-tool build.sh (no universal target matrix)
       |
  verify artifact / router ELF compatibility
       |
  .ipk / .apk / .tgz + build-info.txt + SHA256SUMS
       |
  Actions artifact
       |
  optional manual GitHub Release (default off)
```

## Target isolation

- **Entware AArch64**: `entware-aarch64` uses aarch64-k3.10, glibc 2.27.
  Nginx uses the bundled Entware GCC toolchain and native IPK recipes. Btop instead uses
  GCC 15.2/musl to generate a fully static C++23 binary, packaged as
  `aarch64-3.10` IPK.
- **Entware ARMv7**: `entware-armv7` is armv7sf-k3.2, **soft-float**,
  glibc 2.27. Nginx uses a separate Entware `armv7-3.2` GCC8 toolchain
  and its matching native IPK recipes. Btop uses static GCC 15.2
  `armv7-unknown-linux-musleabi`. Vaultwarden uses `arm-unknown-linux-gnueabi`
  (ARMv6/soft-float, Linux 3.2+, compatible with ARMv7), Zig and glibc
  2.27; do **not** use `armv7-unknown-linux-gnueabi` as it requires Linux
  4.15+. All three produce `armv7-3.2` IPKs.
  None of the newly enabled ARMv7 builds has passed device testing.
- **ABI checks**: Verify architecture, ARMv7 soft-float calling convention,
  loader path (for dynamic programs), and glibc <= 2.27. A static musl
  binary must have neither an ELF interpreter nor shared dependencies.
- **Android**: Librera and MuPDF native build share a workspace. The
  patched MuPDF provides WebP, JPEG XL and reflow support to the patched
  Librera Gradle/NDK integration. APKs are signed using GitHub environment secrets.
- **Windows**: BusyBox-w32 only, using MinGW.
- **Linux**: independent native/cross tool recipes, no unsupported targets.

## Simple recipe contract

`tool.conf` defines `SOURCE_URL`, `SOURCE_REF`, space-delimited `TARGETS`,
and `DEPS`. The runner exports `ROOT`, `WORKSPACE`, `SRC`, `OUT`,
`TARGET`, and `TOOL` to `build.sh`. `TOOLBOX_MUPDF_REF` overrides only
Librera's dependency ref. The common upstream ref is exported as
`TOOLBOX_UPSTREAM_REF`; for nginx it selects an exact signed X.Y.Z source
release, while an empty ref selects the latest stable release. Other tools
accept Git branches, tags or commits. Prefer exact refs over floating branches
for reproducibility.

There is one optional `custom.patch` for each project. It is applied once
to fresh source and never committed back to the upstream repository.
Submodules are synchronized after applying patches.

## IPK format and installation

`scripts/ipk.sh` creates an opkg-style gzip/tar IPK with `debian-binary`,
`control.tar.gz` and `data.tar.gz`. The payload is staged under `/opt`;
no package installs to `/usr` or writes to the router during CI. Existing
nginx IPKs continue to use the Entware package build system directly.
Deployment, init configuration and router runtime smoke testing are manual.

## Failure boundaries

- Fetch/tag failure -> stop
- Patch mismatch -> stop, update custom.patch
- Missing SDK/toolchain -> stop
- Missing expected binary or invalid ABI -> stop
- Build/validation failure -> stop
- No successful artifact -> no release

A successful source preparation is **not** evidence of successful native
compilation or runtime compatibility. Keep the latest verified upstream commit
pair for Librera/MuPDF when debugging new upstream changes.

## Build environments (GitHub only)

`scripts/run.sh` selects a builder for the requested tool/target. It runs the
unchanged source preparation and `build.sh` inside the selected environment:

| Build environment | Tools | Image |
| --- | --- | --- |
| Entware aarch64-k3.10 | nginx, btop | `ghcr.io/vm75/toolbox/entware-aarch64:v3` |
| Entware armv7sf-k3.2 | nginx, btop | `ghcr.io/vm75/toolbox/entware-armv7:v2` |
| Android SDK/NDK | Librera, Cryptomator, Android MuPDF | `ghcr.io/vm75/toolbox/android:ndk-r27d` |
| GitHub Ubuntu 24.04 | Everything else, including router Vaultwarden for both Entware targets (Rust/Zig) | No custom image |

The image name describes the *cross-compilation target*, not the container
architecture. All three builders run as `linux/amd64` on a GitHub-hosted Ubuntu
runner and produce the requested target output.

The `Build toolbox images` workflow builds **only the selected image** and
publishes it to GHCR on manual dispatch. `Build toolbox tool` pulls that image,
bind-mounts the checkout, and runs `scripts/build.sh`. It never implicitly
builds or updates a missing image. Android signing secrets are mounted read-only
at build time, never included in the image. `prepare_only=true` skips images,
SDK installation and signing entirely.

No self-hosted runner, separate external cache service, automatic image
publication, or all-target build matrix is used. The image itself contains
the expensive fixed toolchain; upstream tool sources remain ephemeral.
See [build-images.md](build-images.md) for manual setup and versioning.
