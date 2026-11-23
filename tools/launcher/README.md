# Launcher helper (local-only)

The legacy shenv `make-launcher` and Windows launcher template are retained under
`assets/` as references, but **no GitHub Actions target is exposed**: this script
depends on local Windows utilities (`iconsext.exe`, Digital Mars `dmc.exe`,
UPX and configured filesystem paths). A CI recipe would not be reproducible
without replacing those dependencies. Run manually with your shenv environment.
