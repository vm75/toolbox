# Android APK signing and GitHub Actions secrets

Toolbox builds Android APKs **only on manual dispatch**. Signed
`librera/android-arm64` and `cryptomator/android-arm64` builds require
persistent PKCS#12 keys. GitHub does not provide keys automatically.

## 1. Create or reuse a keystore

Prefer the *original* keystore if you want updates to install over your
existing custom APK. Creating a new key changes the app signing identity.

For a NEW key (example for Librera):

```sh
keytool -genkeypair -storetype PKCS12 \
  -keystore librera-release.p12 -alias librera-release \
  -keyalg RSA -keysize 3072 -validity 10000 \
  -dname "CN=Librera custom build"
keytool -list -v -keystore librera-release.p12 -storetype PKCS12
base64 < librera-release.p12 | tr -d '\n' > librera-release.base64
```

**Do not commit** the `.p12`, its base64 form, passwords or
`google-services.json` to toolbox. Back up the keystore and credentials
offline in a protected location. Losing them prevents updating an installed
APK signed with that key.

## 2. Configure repository Actions secrets

Go to **vm75/toolbox → Settings → Secrets and variables → Actions →
Repository secrets**, then add:

| Librera secrets | Meaning |
| --- | --- |
| `LIBRERA_KEYSTORE_BASE64` | One-line base64-encoded PKCS#12 file |
| `LIBRERA_STORE_PASSWORD` | Keystore password |
| `LIBRERA_KEY_ALIAS` | Existing alias in PKCS#12 |
| `LIBRERA_KEY_PASSWORD` | Key password |

For Cryptomator use separate secrets:
`CRYPTOMATOR_KEYSTORE_BASE64`, `CRYPTOMATOR_STORE_PASSWORD`,
`CRYPTOMATOR_KEY_ALIAS`, `CRYPTOMATOR_KEY_PASSWORD`.

For example, if you use GitHub CLI rather than the Settings page:

```sh
gh secret set LIBRERA_KEYSTORE_BASE64 < librera-release.base64
gh secret set LIBRERA_STORE_PASSWORD
gh secret set LIBRERA_KEY_ALIAS
gh secret set LIBRERA_KEY_PASSWORD
```

Never pass passwords as command-line arguments to `gh secret set` or leave
encoded key material in your Git history. The workflow decodes the chosen
keystore in the runner's temporary directory with restrictive permissions.

## 3. Run a manual build

In **Actions → Build toolbox tool → Run workflow**, choose:

- `tool=librera`, `target=android-arm64`, or
- `tool=cryptomator`, `target=android-arm64`.

Leave `publish_release=false` for a first test. If the build passes,
download the Actions artifact and verify the APK's signing certificate:

```sh
apksigner verify --verbose --print-certs my-custom.apk
```

Compare its SHA-256 signer fingerprint to the intended certificate.
For update compatibility, the signing identity, Android package ID,
version code and installed app build variant must match expectations.
Google Play or F-Droid-signed APKs may not be updateable by these builds.

## Services and third-party API keys

Some flavors of Librera and Cryptomator require Google Drive/other provider
credentials for specific cloud features. Keys are **not** imported from shenv
or hard-coded into patches. Provision only the keys needed for a flavor,
via scoped Actions secrets and/or the build provider's documented integration.
Default builds should not rely on a checked-in service account JSON file.
Do not disable provider security checks or distribute private service secrets.

## GitHub permissions

Enable repository **Actions** execution in Settings. A separate
`publish_release` checkbox controls optional Releases; keep it off by default.
GitHub `GITHUB_TOKEN` is used to publish when explicitly enabled, not a
personal access token. Container-image publishing uses the *separate*
manual `Build Entware toolchain image` workflow with `packages: write`.

These workflows do not contain push, pull request, tag or scheduled triggers.
