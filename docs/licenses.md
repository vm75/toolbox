# Licenses and origin of incorporated material

**Toolbox's new orchestration scripts and documentation** use the MIT license
in [../LICENSE](../LICENSE). This does not relicense imported or patched code.

| Project | Origin | License / notice |
| --- | --- | --- |
| nginx builder | [vm75/maestro](https://github.com/vm75/maestro) | MIT; attribution retained |
| MuPDF patch | [ArtifexSoftware/mupdf](https://github.com/ArtifexSoftware/mupdf) and [vm75/mupdf](https://github.com/vm75/mupdf) | AGPL-3.0 or commercial licensing from Artifex |
| Librera patch | [foobnix/LibreraReader](https://github.com/foobnix/LibreraReader) and [vm75/LibreraReader](https://github.com/vm75/LibreraReader) | Upstream `LICENSE.txt` plus bundled component licenses |
| btop | [aristocratos/btop](https://github.com/aristocratos/btop) | Apache-2.0 |
| Vaultwarden | [dani-garcia/vaultwarden](https://github.com/dani-garcia/vaultwarden) | AGPL-3.0 |
| BusyBox-w32 | [rmyorston/busybox-w32](https://github.com/rmyorston/busybox-w32) | GPL-2.0 |
| Cryptomator Android | [cryptomator/android](https://github.com/cryptomator/android) | GPL-3.0 / commercial dual licensing |
| rsync | [RsyncProject/rsync](https://github.com/RsyncProject/rsync) | GPL, see upstream COPYING |
| John the Ripper jumbo | [magnumripper/JohnTheRipper](https://github.com/magnumripper/JohnTheRipper) | Upstream component licenses |
| wireguard-go | [WireGuard/wireguard-go](https://github.com/WireGuard/wireguard-go) | MIT |
| wg-util | [vm75/wg-util](https://github.com/vm75/wg-util) | See upstream repository |

The patches are deltas against third-party source, not a grant of a new license.
Check each upstream license, generated binary distribution requirements, source
availability, notices and patent conditions before making public binary
releases. Do not represent AGPL/GPL components as MIT. Codec packages and
web-vault bundles have their own license obligations.

The `tools/nginx/upstream-builder.sh` file was adapted from the original
Maestro builder. Custom BusyBox/Cryptomator patch deltas and the retained
runtime helper assets are project-specific modifications, not a grant of any
new upstream license. No local secret files or proprietary compiler binaries
are included.
