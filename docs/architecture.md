# Architecture

```text
manual workflow_dispatch (tool + compatible target + optional refs)
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
