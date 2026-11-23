# Working on toolbox

## Intent

Keep builds boring: **KISS, YAGNI, DRY**. Toolbox is not a fork mirror, package
registry, generalized CI framework, or all-platform build farm.

## Repository map

- `scripts/build.sh`: one upstream fetch, dependency preparation and patch gate
- `scripts/ipk.sh`, `scripts/check-router-elf.sh`: router packaging and ELF checks
- `tools/<tool>/tool.conf`: trusted source URL, ref, allowed target list, dependencies
- `tools/<tool>/build.sh`: only commands needed for that particular tool
- `tools/<tool>/custom.patch`: **one optional patch** relative to clean upstream
- `.github/workflows/`: **workflow_dispatch ONLY**, release opt-in

## Rules

1. Do not vendor complete upstream source trees or copy a fork into this repository.
2. Do not add per-tool platform matrices; declare only explicitly supported targets.
3. Do not split patches into multiple files without an actual independent feature
   that justifies the complexity.
4. Stop immediately on patch failure or incompatible router ELF; never suppress errors.
5. For Librera, prepare patched MuPDF first and pass its path as LIBRERA_MUPDF_DIR.
6. No automatic build, tag, push, cron, PR or release triggers. Release publishing
   must remain a manual opt-in and run only after a successful build.
7. Never commit keystores, private keys, Google service credentials or tokens.
8. Preserve attribution, third-party licenses, sources and reproducible inputs.
9. Prefer reuse of Maestro nginx's tested Entware build system over a second one.
10. Avoid additional build DSLs, package managers or dependencies without need.

## Review checklist

- Run `bash scripts/test.sh`.
- Test source preparation against the intended ref with `TOOLBOX_PREPARE_ONLY=1`.
- Test the actual binary/APK and, for routers, install on a disposable/test device.
- Inspect binary ABI and dependency requirements before distributing IPKs.
- Record the upstream commit and patch SHA; verify release checksums.
- Treat a patch applying cleanly as **necessary but not sufficient** for correctness.

This repository contains source-derived patches for MuPDF and Librera; future
upstream changes may require manual source adaptation. Never claim a green build
without logs or artifact inspection.
