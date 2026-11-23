# Licenses and origin of incorporated material

**Toolbox's new orchestration scripts and documentation** use the MIT license
in [../LICENSE](../LICENSE). This does not relicense imported or patched code.

| Project | Origin | License / notice |
| --- | --- | --- |
| nginx builder | In-tree `tools/nginx/upstream-builder.sh` | MIT; copyright and license notices retained |
| GCC 15.2 musl cross-compilers (builder images only) | [cross-tools/musl-cross](https://github.com/cross-tools/musl-cross/releases/tag/20250929) | GCC, binutils and musl retain their respective GPL/runtime-exception and MIT licenses; observe source redistribution requirements for published GHCR images |
| MuPDF patch | [ArtifexSoftware/mupdf](https://github.com/ArtifexSoftware/mupdf) and [vm75/mupdf](https://github.com/vm75/mupdf) | AGPL-3.0 or commercial licensing from Artifex |
| Librera patch | [foobnix/LibreraReader](https://github.com/foobnix/LibreraReader) and [vm75/LibreraReader](https://github.com/vm75/LibreraReader) | Upstream `LICENSE.txt` plus bundled component licenses |
| btop | [aristocratos/btop](https://github.com/aristocratos/btop) | Apache-2.0 |
| Vaultwarden | [dani-garcia/vaultwarden](https://github.com/dani-garcia/vaultwarden) | AGPL-3.0 |
| BusyBox-w32 | [rmyorston/busybox-w32](https://github.com/rmyorston/busybox-w32) | GPL-2.0 |
| Cryptomator Android | [cryptomator/android](https://github.com/cryptomator/android) | GPL-3.0 / commercial dual licensing |
| John the Ripper jumbo | [magnumripper/JohnTheRipper](https://github.com/magnumripper/JohnTheRipper) | Upstream component licenses |
| wireguard-go | [WireGuard/wireguard-go](https://github.com/WireGuard/wireguard-go) | MIT |
| wg-util | [vm75/wg-util](https://github.com/vm75/wg-util) | See upstream repository |

The patches are deltas against third-party source, not a grant of a new license.
Check each upstream license, generated binary distribution requirements, source
availability, notices and patent conditions before making public binary
releases. Do not represent AGPL/GPL components as MIT. Codec packages and
web-vault bundles have their own license obligations.

The nginx cross-builder is maintained directly in this repository and uses
Entware's build system and upstream nginx releases; it does not fetch an
external cross-builder repository. Its existing copyright and license
obligations remain in effect. Custom BusyBox/Cryptomator patch deltas and the
retained runtime helper assets are project-specific modifications, not a grant
of any new upstream license. No local secret files or proprietary compiler
binaries are included.
