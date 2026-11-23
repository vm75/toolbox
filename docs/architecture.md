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

- **Router**: Entware aarch64-k3.10 (glibc 2.27) exactly as in Maestro.
  Nginx uses its native Entware IPK recipes; btop uses the shared Entware
  toolchain and the common IPK packager; Vaultwarden uses Zig/Rust's explicit
  aarch64 GNU glibc-2.27 target and the same packager. Reject generic ARM64
  binaries whose interpreter or glibc requirements do not match.
- **Android**: Librera and MuPDF native build share a workspace. The
  patched MuPDF provides WebP, JPEG XL and reflow support to the patched
  Librera Gradle/NDK integration. APKs are signed from GitHub Secrets.
- **Windows**: BusyBox-w32 only, using MinGW.
- **Linux**: independent native/cross tool recipes, no unsupported targets.

## Simple recipe contract

`tool.conf` defines `SOURCE_URL`, `SOURCE_REF`, space-delimited `TARGETS`,
and `DEPS`. The runner exports `ROOT`, `WORKSPACE`, `SRC`, `OUT`,
`TARGET`, and `TOOL` to `build.sh`. `TOOLBOX_MUPDF_REF` overrides only
Librera's dependency ref. For reproducibility, pass exact upstream commit
IDs instead of floating branch names.

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
| Entware aarch64-k3.10 | nginx, btop | `ghcr.io/vm75/toolbox/entware-aarch64:v1` |
| Android SDK/NDK | Librera, Cryptomator, Android MuPDF | `ghcr.io/vm75/toolbox/android:ndk-r27d` |
| GitHub Ubuntu 24.04 | Everything else, including router Vaultwarden (Rust/Zig) | No custom image |

The image name describes the *cross-compilation target*, not the container
architecture. Both builders run as `linux/amd64` on a GitHub-hosted Ubuntu
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
