# toolbox

Build personal tools from **clean upstream source** on demand. This repo stores
small target-specific build recipes and at most one `custom.patch` per tool;
it does **not** mirror or rebase upstream repositories. The router nginx build is based on the
[Maestro nginx cross-builder](https://github.com/vm75/maestro).

## Quick start

Use **Actions → Build toolbox tool → Run workflow**. Pick a tool and one of
its supported targets. The workflow downloads upstream, applies
`tools/<tool>/custom.patch` when present, builds and uploads artifacts.
**No Actions build or release runs on push, PR, tag, release or a schedule.**
The `publish_release` checkbox defaults to **false**. Publishing is a separate
step inside the *manually dispatched* build after success.

Before the first full nginx, btop or Android build, manually publish its builder
image using **Actions → Build toolbox images → Run workflow**. Select
`entware-aarch64`, `entware-armv7` or `android` as required. The images are
stored in GHCR and reused across
tool builds; no image is built automatically. See [builder images](docs/build-images.md).
A `prepare_only=true` patch check works without any builder image.

To run locally (requires the target's compiler/SDK):

```sh
bash scripts/build.sh btop entware-aarch64
bash scripts/build.sh librera android-arm64
TOOLBOX_MUPDF_REF=1.28.5 bash scripts/build.sh librera android-arm64 10.0.7
TOOLBOX_PREPARE_ONLY=1 bash scripts/build.sh mupdf android-arm64
```

Delete `.work/` between runs; source trees must be fresh. Set
`TOOLBOX_WORKDIR` and `TOOLBOX_OUTPUT` to move working files and outputs.

## Supported targets

Only listed combinations are supported; the build runner rejects all others.

| Tool | Target(s) | Source / special handling |
| --- | --- | --- |
| nginx | entware-aarch64 | Maestro-derived Entware cross-builder; nginx and matching module IPKs |
| btop | entware-aarch64, entware-armv7 | Latest upstream + GCC 15.2 musl static cross-build; IPK for either Entware ABI |
| vaultwarden | entware-aarch64, linux-amd64, linux-arm64, linux-armv7 | Zig/Rust glibc 2.27 cross-build for Entware AArch64 IPK; upstream Docker for other Linux targets |
| mupdf | linux-amd64, android-arm64 | Patched MuPDF; Android source prepared for dependent Librera native build |
| librera | android-arm64 | Depends on patched MuPDF checkout; signed F-Droid APK |
| busybox | windows-amd64 | MinGW BusyBox-w32 |
| cryptomator | android-arm64 | Signed APK; local customization patch |
| rsync | linux-amd64 | Native source build |
| john | linux-amd64 | John the Ripper jumbo source build |
| wireguard | linux-amd64, linux-arm64, linux-armv7 | wireguard-go plus wg-util |
| wg-util | linux-amd64, linux-arm64, linux-armv7 | Key utility from vm75/wg-util |

`entware-aarch64` means **Entware aarch64-k3.10** (not generic Linux ARM64);
`entware-armv7` means **Entware armv7sf-k3.2**, with the 32-bit soft-float
ABI (not hard-float). Both have glibc 2.27 for dynamically linked programs.
IPKs are generated for nginx (AArch64), btop (both), and Vaultwarden
(AArch64). Entware ARMv7 currently supports btop only; nginx's build and
Vaultwarden's current Rust target are not validated for Linux 3.2. Btop is built *fully static* with pinned GCC 15.2/musl, not Entware's
older GCC 8.4; verify on the actual device before deploying.
The Actions run table displays the selected tool and target as its run name.

## Upstream updates and patch failures

A tool with no `custom.patch` builds upstream unmodified. MuPDF and Librera
each have **one** independently versioned patch extracted from their respective
forks. When the new upstream revision cannot accept a patch,
`git apply --check` exits nonzero and no build
or release is published. Update that one patch locally; **no upstream fork
push, rebase of published history, or automatic conflict resolution** is needed.
See [patch maintenance](docs/patches.md).

The patch stacks were extracted from the last published custom fork code.
**Compatibility with November 2026 upstream tips and successful full builds
have not yet been verified**. Until each target is validated, use explicit
upstream revisions for repeatability and expect patch or upstream API changes
to require code work.

## Documentation

- [Architecture and dependency flow](docs/architecture.md)
- [GHCR builder images and manual setup](docs/build-images.md)
- [Maintaining one patch per tool](docs/patches.md)
- [Android signing keys and GitHub setup](docs/android-signing.md)
- [Licenses and upstream notices](docs/licenses.md)
- [AGENTS.md](AGENTS.md) for contributors and coding assistants

## Security and release policy

GitHub Actions is manual-only. Source pins are recorded in `dist/build-info.txt`,
along with patch hashes, checksums and any packaged IPKs/APKs. A second
manual-only workflow publishes **three versioned builder images**:
`entware-aarch64:v2`, `entware-armv7:v1` and `android:ndk-r27d`.
Nginx/btop and Librera/Cryptomator use these images without rebuilding their
toolchains on each run. Vaultwarden, Go tools and native Linux/Windows builds remain on
GitHub-hosted Ubuntu; no self-hosted runners or external caches are used.
Missing builder images fail clearly: run the manual image workflow first.
**Warning: Never commit private keys, Android signing keystores, passwords,
tokens or Google API credentials to this repository.** Toolbox has no
`tools/keys` directory and does not store signing files. Signed Android builds
use app-specific GitHub Actions **environment secrets**, configured under
**Settings → Environments → android-signing → Environment secrets**. The workflow temporarily
provides those secrets to the Android build; they are not baked into GHCR
builder images. See [Android signing](docs/android-signing.md). If you don't
configure signing secrets, signed APK builds will fail rather than publish an
unsigned or incorrectly signed release.
