# Builder images (GitHub Actions + GHCR only)

Toolbox has **three** reusable build environments, not one image per tool. There
are two Entware architectures and one Android SDK.

| Builder | Default tag | Used for | Important contents |
| --- | --- | --- | --- |
| `entware-aarch64` | `v3` | nginx, btop | Maestro Entware aarch64-k3.10 GCC 8.4 for nginx; GCC 15.2 musl for static btop |
| `entware-armv7` | `v2` | nginx, btop (armv7sf-k3.2) | Entware GCC8/glibc 2.27 and GCC 15.2 musl ARMv7 *soft-float* |
| `android` | `ndk-r27d` | Librera, Cryptomator, Android MuPDF | JDK 21, API 37, build-tools 37.0.0, NDK 27.2.12479018, CMake 3.22.1 |

Both containers run on GitHub's `ubuntu-24.04` AMD64 runner. The target name
refers to what the cross-compiler produces, not to an emulated container CPU.
Everything else builds directly on the normal GitHub-hosted runner. In particular,
Vaultwarden for both Entware targets uses Rust + Zig on that runner. It installs
Rust's target standard library **inside the upstream source checkout**, after
its rust-toolchain override is selected (the former early installation caused
E0463). ARMv7 uses Rust's ARMv6-compatible soft-float GNU target to preserve
the Linux 3.2 baseline, rather than the native ARMv7 target requiring 4.15+.

## Initial setup (manual, once per image)

1. In repository **Settings → Actions**, ensure actions are enabled.
2. In **Actions → Build toolbox images → Run workflow**, select
   `entware-aarch64` and run it. It builds the Entware cross-toolchain plus
   installs a SHA-256-pinned GCC 15.2 musl AArch64 cross-compiler.
3. Repeat for `entware-armv7` if building ARMv7 nginx/btop, or `android` if
   building APKs. ARMv7 now bootstraps its own Entware `armv7-3.2`
   toolchain (the first build can take significant time and disk space).
4. The resulting packages are published to the repository's GHCR namespace:
   - `ghcr.io/vm75/toolbox/entware-aarch64:v3`
   - `ghcr.io/vm75/toolbox/entware-armv7:v2`
   - `ghcr.io/vm75/toolbox/android:ndk-r27d`

The publishing workflow has `packages: write` permission and authenticates
to GHCR using the built-in GitHub token. For private packages, grant this
repository Actions read access in the GHCR package settings. Tool builds have
`packages: read`; no personal access tokens or external registries are needed.

## Running a build

Use **Actions → Build toolbox tool → Run workflow**. Choose one tool and
one supported target. `scripts/run.sh` selects the matching builder,
authenticates to GHCR, pulls the image, mounts the repository, and invokes
the normal `scripts/build.sh` script.

Builds *fail with instructions* if a required builder image is absent.
They do **not** rebuild SDKs or toolchains as a fallback. For a quick
upstream patch compatibility check, set `prepare_only=true`, which uses
the normal Ubuntu runner and does not pull any builder image.

`builder_image_tag` on the tool workflow optionally overrides the selected
image tag. The image publishing workflow also has a `tag` override; choose
matching tags if you publish a test image. By default both use the versioned
tags in the table above.

## Updating images

Edit a Dockerfile under `images/`, then **manually** run the image
publishing workflow for the updated builder. Prefer changing the versioned
tag (e.g. `v2`) for breaking toolchain updates, then update the default
tag in `scripts/run.sh`. For strict reproducibility, record the published
image digest alongside source SHAs before distributing artifacts.

`images/entware-aarch64/Dockerfile` reuses the existing Maestro-derived
nginx toolchain bootstrap, adding the GCC 15.2 musl compiler for btop.
`images/entware-armv7/Dockerfile` also builds Entware's **ARMv7** toolchain
for nginx and installs the separate modern ARMv7 soft-float musl compiler for
btop. Both use pinned release SHA-256 checksums from
[cross-tools/musl-cross](https://github.com/cross-tools/musl-cross/releases/tag/20250929)
and never install compilers during normal tool builds. `images/android/Dockerfile` verifies the SHA-256
of Google's pinned command-line-tools archive before installing Android
packages. Keep APK signing secrets in GitHub Actions only.

No push, PR, schedule or tag automatically builds or releases an image.
Neither tool builds nor image builds use a separate dependency cache,
self-hosted machines or a per-platform build matrix.
