# Builder images (GitHub Actions + GHCR only)

Toolbox has **two** reusable build environments, not one image per tool.

| Builder | Default tag | Used for | Important contents |
| --- | --- | --- | --- |
| `entware-aarch64` | `v1` | nginx, btop (router IPKs) | Maestro-derived Entware aarch64-k3.10 toolchain and sysroot |
| `android` | `ndk-r27d` | Librera, Cryptomator, Android MuPDF | JDK 21, API 37, build-tools 37.0.0, NDK 27.2.12479018, CMake 3.22.1 |

Both containers run on GitHub's `ubuntu-24.04` AMD64 runner. The target name
refers to what the cross-compiler produces, not to an emulated container CPU.
Everything else builds directly on the normal GitHub-hosted runner. In particular,
router Vaultwarden still uses Rust + Zig on that runner; a third image would
add maintenance without yet proving a meaningful time saving.

## Initial setup (manual, once per image)

1. In repository **Settings → Actions**, ensure actions are enabled.
2. In **Actions → Build toolbox images → Run workflow**, select
   `entware-aarch64` and run it. This can take substantial CPU, time and
   disk space because it builds the Entware cross-toolchain.
3. Repeat for `android`. That image downloads the pinned Android SDK/NDK
   and command-line tools.
4. The resulting packages are published to the repository's GHCR namespace:
   - `ghcr.io/vm75/toolbox/entware-aarch64:v1`
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
nginx toolchain bootstrap. `images/android/Dockerfile` verifies the SHA-256
of Google's pinned command-line-tools archive before installing Android
packages. Keep APK signing secrets in GitHub Actions only.

No push, PR, schedule or tag automatically builds or releases an image.
Neither tool builds nor image builds use a separate dependency cache,
self-hosted machines or a per-platform build matrix.
