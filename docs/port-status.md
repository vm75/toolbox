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

Router cross-builds are also **not yet verified**. Vaultwarden's GNU glibc
cross toolchain and btop's contemporary C++ requirements may need additional
compiler/recipe changes. Do not deploy generated IPKs until they pass device
checks, dependency checks and rollback tests.
