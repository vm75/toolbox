# Status of latest upstream ports

Last inspected: 2026-11-23. This is a source-level comparison, **not** a green
CI build or successful runtime test.

| Project | Custom base | Current upstream state | Result |
| --- | --- | --- | --- |
| MuPDF | `a9642221980b092bb60b2e2ef79aa2e97bfb12eb` | 82 commits beyond the patch's original base; only 5 source files modified on both sides | Updated Makefile hunk context; full `git apply` and codec builds still need validation |
| LibreraReader | `31147f3eefb4c7b887aa31bd27916c5b6cc916e5` | 127 commits beyond original base; 16 overlapping changed files and 2 deleted native-build files | Needs a deliberate port of the MuPDF integration before latest upstream APK build can be considered supported |

For Librera, the upstream changes include `app/build.gradle`,
`AndroidManifest.xml`, build scripts, `BookType`, image extractors, and JNI
build configuration. The older fork's `Builder/build-nomupdf.sh` and
`Builder/jni/Android-nomupdf.mk` are no longer in current upstream. Do not
blindly force those files over upstream's newer implementation.

The repo keeps **one patch per tool** and uses `git apply --check` as the first
gate. Run a cheap patch probe from **Actions → Build toolbox tool → Run
workflow** with `prepare_only=true`; this will fetch upstream and inspect
patch compatibility without invoking compilers or publishing any release.

When the check fails: port the old fork's feature onto the *new* upstream tree
in a temporary checkout, regenerate the single `custom.patch`, and rerun the
probe. For Librera, validate against the independently patched MuPDF checkout,
then run JNI + Gradle + device tests. The fork itself does not need to be
rebased or pushed for toolbox to build.

## Entware tool builds

| Tool / target | Source | Cross-compiler | Status |
| --- | --- | --- | --- |
| btop / entware-aarch64 | upstream `main` (user-verified example `cece4df4db2112f63d94347f6ee2f89ee7224c7b`) | Pinned GCC 15.2 musl, static | Recipe updated; **CI/IPK validation pending** |
| btop / entware-armv7 | upstream `main` | Pinned GCC 15.2 armv7-musleabi, static | New cross-target; **CI and device test pending** |
| nginx / entware-aarch64 | upstream stable | Entware GCC 8.4/glibc 2.27 | Existing dedicated Entware build; not retested |
| nginx / entware-armv7 | upstream stable | Entware armv7-3.2 GCC 8.4/glibc 2.27 | New build target, not yet tested |
| Vaultwarden / entware-aarch64 | upstream `main` | Rust + Zig targeting glibc 2.27 | Rust target install fixed; rerun pending |
| Vaultwarden / entware-armv7 | upstream `main` | Rust ARMv6 GNU soft-float + Zig/glibc 2.27 | New recipe; CI/device validation pending |

[Failed btop run 45242586997](https://github.com/vm75/toolbox/actions/runs/45242586997):
the Entware cross-toolchain was built successfully, then GCC **8.4.0** failed
on upstream btop 1.4.8's `-std=c++23`. This is a *compiler mismatch*, not a
patch conflict. The replacement btop recipe uses the same GCC 15.2/static
musl approach reported to work with btop 1.4.7+cece4df. The toolchain
tarballs are pinned to release `cross-tools/musl-cross@20250929` with
SHA-256 verification in `images/install-musl-toolchain.sh`. CI with the
current upstream and the ARMv7 soft-float ABI still needs testing.

[Failed Vaultwarden run 45251401473](https://github.com/vm75/toolbox/actions/runs/45251401473):
upstream `rust-toolchain.toml` selected Rust 1.100, but `rustup target add`
previously installed the AArch64 target for the runner default Rust toolchain.
The resulting E0463 "can't find crate for core" is addressed by installing
the correct target inside the source checkout before compilation. ARMv7 is
enabled with the ARMv6 soft-float Rust GNU target for the Linux 3.2 kernel,
not the native ARMv7 Rust target requiring Linux 4.15+.
Do not deploy generated IPKs without
architecture/runtime checks, a disposable-device test, and rollback steps.
