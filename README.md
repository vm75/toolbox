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
image using **Actions → Build toolbox images → Run workflow**. Select either
`entware-aarch64` or `android`. Both are stored in GHCR and reused across
tool builds; no image is built automatically. See [builder images](docs/build-images.md).
A `prepare_only=true` patch check works without any builder image.

To run locally (requires the target's compiler/SDK):

```sh
bash scripts/build.sh btop router-aarch64
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
| nginx | router-aarch64 | Maestro-derived Entware cross-builder; produces nginx and matching module IPKs |
| btop | router-aarch64 | Latest upstream + Entware C++ cross-compiler; IPK |
| vaultwarden | router-aarch64, linux-amd64, linux-arm64, linux-armv7 | Entware-compatible glibc build for router/IPK; upstream Docker build for other targets |
| mupdf | linux-amd64, android-arm64 | Patched MuPDF; Android source prepared for dependent Librera native build |
| librera | android-arm64 | Depends on patched MuPDF checkout; signed F-Droid APK |
| busybox | windows-amd64 | MinGW BusyBox-w32 |
| cryptomator | android-arm64 | Signed APK; local customization patch |
| rsync | linux-amd64 | Native source build |
| john | linux-amd64 | John the Ripper jumbo source build |
| wireguard | linux-amd64, linux-arm64, linux-armv7 | wireguard-go plus wg-util |
| wg-util | linux-amd64, linux-arm64, linux-armv7 | Key utility from vm75/wg-util |

`router-aarch64` specifically means the **Entware aarch64-k3.10**
environment used by Maestro, not generic Linux ARM64. IPK is generated for
nginx, btop and Vaultwarden only; router binaries are checked for the AArch64
ELF target, dynamic loader and glibc version before packaging. Cross-compiling
does not replace testing on your router.

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
manual-only workflow publishes **two versioned builder images**:
`entware-aarch64:v1` and `android:ndk-r27d`. Nginx/btop and
Librera/Cryptomator use these images without repeating the SDK/toolchain
installation. Vaultwarden, Go tools and native Linux/Windows builds remain on
GitHub-hosted Ubuntu; no third builder image or external cache is needed.
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
