# Patch maintenance

Use **one `custom.patch` per tool**, or none for build-only differences.
The patch should contain source changes only, while build commands and
target packaging live in `build.sh`.

## Creating or updating a patch

Work in a temporary clone of the upstream repository, outside toolbox:

```sh
git clone https://github.com/ArtifexSoftware/mupdf.git /tmp/mupdf-upstream
cd /tmp/mupdf-upstream
git checkout master
git switch -c toolbox-local
git apply /path/to/toolbox/tools/mupdf/custom.patch
# Adapt any rejected hunks / API differences in a local editor.
# Commit your adaptations, then produce the consolidated delta:
git add -A
git commit -m "Port my changes to current upstream"
git diff --binary master HEAD > /path/to/toolbox/tools/mupdf/custom.patch
```

If `git apply` fails, use the previous known-good upstream revision to
reconstruct the customization, then port changes forward. No published fork
branch needs rebasing. For the original custom patches, the bases were:
- MuPDF: `a9642221980b092bb60b2e2ef79aa2e97bfb12eb`
- Librera: `31147f3eefb4c7b887aa31bd27916c5b6cc916e5`

For Librera, use `foobnix/LibreraReader` as upstream and update its
`tools/librera/custom.patch` independently. Run source preparation for **both**
projects, then build Librera against the patched MuPDF checkout.

The initial code patches were exported from the fork diffs; they exclude
fork-only rebase automation, documentation and binary test fixtures. Ensure
newly introduced binary fixtures/licenses are preserved when required and
reintroduce any targeted tests needed to validate upstream refactors.

## Verification

```sh
rm -rf .work dist
TOOLBOX_PREPARE_ONLY=1 bash scripts/build.sh mupdf android-arm64
rm -rf .work dist
TOOLBOX_PREPARE_ONLY=1 bash scripts/build.sh librera android-arm64
```

A clean patch check is only the first gate. Follow it with codec tests,
Gradle unit/device tests and signed APK install validation.

Git itself can generate binary patches (`git diff --binary`) when needed,
but keep large binary test assets out of toolbox unless they directly support
essential verification. Document exact upstream commits for each validated pair.
