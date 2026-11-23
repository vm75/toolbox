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

## 2. Configure GitHub Actions environment secrets

Go to **vm75/toolbox → Settings → Environments** and create an environment
named **`android-signing`**. Inside that environment, add these
**Environment secrets** (not repository secrets):

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
gh secret set LIBRERA_KEYSTORE_BASE64 --env android-signing < librera-release.base64
gh secret set LIBRERA_STORE_PASSWORD --env android-signing
gh secret set LIBRERA_KEY_ALIAS --env android-signing
gh secret set LIBRERA_KEY_PASSWORD --env android-signing
```

Never pass passwords as command-line arguments to `gh secret set` or leave
encoded key material in your Git history. The workflow decodes the chosen
keystore in the runner's temporary directory with restrictive permissions.

Signed Librera/Cryptomator builds select the `android-signing` environment,
so its secrets are available **only during those manual build jobs**.
Other tools and `prepare_only=true` runs use a secret-free `build`
environment (GitHub creates it automatically if needed). Both select
`deployment: false` to avoid recording builds as GitHub Deployments;
neither build environment installs software anywhere. Existing deployment
history is not deleted. Required-reviewer and wait-timer environment
protection rules still work; custom GitHub App deployment protection rules
are incompatible with `deployment: false`.
No secret *values* or keystores belong in this repository.

## 3. Run a manual build

First use **Actions → Build toolbox images → Run workflow → android** to
publish the Android builder (one-time, or manually whenever its Dockerfile
changes). The image contains the Android SDK, NDK and JDK but **no keys**.
Each APK build decodes its keystore on the GitHub runner and bind-mounts that
file read-only into the container. The key is never committed or baked into
a GHCR image.

Then in **Actions → Build toolbox tool → Run workflow**, choose:

- `librera / android-arm64`, or
- `cryptomator / android-arm64`.

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
credentials for specific cloud features. Credentials are **not** embedded in
custom patches. Provision only the credentials needed for a flavor,
via scoped GitHub environment secrets and/or the build provider's documented integration.
Default builds should not rely on a checked-in service account JSON file.
Do not disable provider security checks or distribute private service secrets.

## GitHub permissions

Enable repository **Actions** execution in Settings. A separate
`publish_release` checkbox controls optional Releases; keep it off by default.
GitHub `GITHUB_TOKEN` is used to publish when explicitly enabled, not a
personal access token. Container-image publishing uses the *separate*
manual `Build toolbox images` workflow with `packages: write`.
Tool builds read existing GHCR packages with `packages: read`.

These workflows do not contain push, pull request, tag or scheduled triggers.
