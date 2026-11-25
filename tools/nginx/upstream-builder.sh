#!/usr/bin/env bash
# Standalone NGINX cross-builder for Entware AArch64 and ARMv7 soft-float.
# Host: Debian, Ubuntu, or Arch Linux (x86_64). Fully contained in toolbox.
# Uses Entware's glibc 2.27 nginx-ssl recipe and per-architecture cross-toolchain.
# Does NOT install anything on the router.
set -Eeuo pipefail
unset CDPATH || true

PROGRAM=${0##*/}
CHANNEL=stable
VERSION=
WORKDIR=${NGINX_BUILD_WORKDIR:-}
ENTWARE_TARGET=aarch64-3.10
OUTPUT_DIR=
# Keep initial cross-toolchain builds conservative; JOBS/--jobs can override.
if [[ -z ${JOBS:-} ]]; then
  JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')
  if (( JOBS > 4 )); then JOBS=4; fi
fi
AUTO_DEPS=1
UPDATE_REPOS=1
TOOLCHAIN_ONLY=0
RECIPE_BACKUP=
RECIPE_FILE=
GPG_HOME=
STAGE_DIR=

usage() {
  cat <<EOF
Usage: $PROGRAM [options]

Cross-compile NGINX for Entware AArch64 or ARMv7 soft-float.
The build is performed on a Debian/Ubuntu/Arch x86_64 host, NOT on the router.

Options:
  --target aarch64-3.10|armv7-3.2  Entware target (default: aarch64-3.10)
  --channel stable|mainline   Upstream release channel (default: stable)
  --stable                    Shortcut for --channel stable
  --mainline                  Shortcut for --channel mainline
  --version X.Y.Z             Build this exact version (skip channel detection)
  --workdir DIR               Persistent Entware build/cache (default: $WORKDIR)
  --output DIR                Destination for binary, IPK and metadata
  --jobs N                    Concurrent build jobs (default: $JOBS)
  --no-install-deps           Do not install missing host packages
  --no-update                 Do not git-pull Entware/build feeds (still fetch release)
  --toolchain-only            Build cross-toolchain and target environment only
  -h, --help                  Show help

Output directory: nginx-X.Y.Z-<entware-target>/
  nginx, nginx-ssl_*.ipk, nginx-mod-{brotli,stream,headers-more}_*.ipk,
  ngx_http_brotli_{filter,static}_module.so, ngx_stream_module.so,
  ngx_http_headers_more_filter_module.so, SHA256SUMS, build-info.txt

NOTES:
  * Requires substantial disk space (10+ GiB recommended), RAM, and internet.
  * Requires a source release signed by one of the four pinned nginx.org keys.
  * Entware recipes may need adjustments for brand-new NGINX versions.
  * Hardened reverse-proxy profile: PIE, SSP, FORTIFY=2, full RELRO.
  * Fixed, broad reverse-proxy profile: HTTP/3, HTTP/2, gRPC, CGI gateways,
    Memcached proxy, TCP/UDP stream, Brotli, headers-more, request limits.
  * Excludes native WebDAV, FLV, SSI, autoindex, tracking/legacy modules,
    njs, GeoIP2, NAXSI, Lua, RTMP and MPEG-TS extensions.
  * NGINX plus matching Brotli, stream and headers-more modules are built.
  * HTTP/3 and stream listeners remain inactive until configured.
  * Custom nginx configs using disabled modules require profile adjustments.
  * NO router installation.
EOF
}

log() { printf '[nginx-build] %s\n' "$*" >&2; }
die() { printf '[nginx-build] ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  # Never leave local changes in the Entware feed. Keeping it clean permits update.
  if [[ -n $RECIPE_BACKUP && -f $RECIPE_BACKUP && -n $RECIPE_FILE ]]; then
    cp -p -- "$RECIPE_BACKUP" "$RECIPE_FILE" || log 'WARNING: could not restore upstream recipe'
    rm -f -- "$RECIPE_BACKUP"
  fi
  if [[ -n $GPG_HOME && -d $GPG_HOME ]]; then rm -rf -- "$GPG_HOME"; fi
  if [[ -n $STAGE_DIR && -d $STAGE_DIR ]]; then rm -rf -- "$STAGE_DIR"; fi
}
trap cleanup EXIT
trap 'log "Failed at line $LINENO: $BASH_COMMAND"' ERR

while (($#)); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || die '--target needs a value'; ENTWARE_TARGET=$2; shift 2 ;;
    --channel) [[ $# -ge 2 ]] || die '--channel needs a value'; CHANNEL=$2; shift 2 ;;
    --stable) CHANNEL=stable; shift ;;
    --mainline) CHANNEL=mainline; shift ;;
    --version) [[ $# -ge 2 ]] || die '--version needs a value'; VERSION=$2; shift 2 ;;
    --workdir) [[ $# -ge 2 ]] || die '--workdir needs a value'; WORKDIR=$2; shift 2 ;;
    --output) [[ $# -ge 2 ]] || die '--output needs a value'; OUTPUT_DIR=$2; shift 2 ;;
    --jobs) [[ $# -ge 2 ]] || die '--jobs needs a value'; JOBS=$2; shift 2 ;;
    --no-install-deps) AUTO_DEPS=0; shift ;;
    --no-update) UPDATE_REPOS=0; shift ;;
    --toolchain-only) TOOLCHAIN_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

case "$ENTWARE_TARGET" in
  aarch64-3.10) EXPECTED_MACHINE=AArch64; PACKAGE_TARGET=aarch64-k3.10 ;;
  armv7-3.2) EXPECTED_MACHINE=ARM; PACKAGE_TARGET=armv7sf-k3.2 ;;
  *) die "Unsupported Entware target: $ENTWARE_TARGET" ;;
esac
WORKDIR=${WORKDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/nginx-entware-$ENTWARE_TARGET}
[[ $CHANNEL == mainline || $CHANNEL == stable ]] || die 'Channel must be mainline or stable'
RELEASE_SELECTION=$CHANNEL
[[ -z $VERSION ]] || RELEASE_SELECTION=explicit
[[ -z $VERSION || $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Invalid --version (expected X.Y.Z)'
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || die 'Invalid --jobs (expected positive integer)'
[[ $(uname -s) == Linux ]] || die 'Linux build host required'
[[ $(uname -m) == x86_64 ]] || die 'This script currently supports x86_64 build hosts only'
(( EUID != 0 )) || die 'Do not run the build as root; script uses sudo only for missing dependencies'
[[ $WORKDIR == /* ]] || WORKDIR="$PWD/$WORKDIR"
[[ $WORKDIR != *[[:space:]]* ]] || die 'Entware build directory cannot contain whitespace'

# Dependency installation: query package manager first; use sudo only if missing.
if [[ ! -r /etc/os-release ]]; then die '/etc/os-release is required'; fi
OS_ID=$(. /etc/os-release && printf '%s' "${ID:-}")
OS_ID_LIKE=$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")
if [[ $OS_ID == arch || " $OS_ID_LIKE " == *" arch "* ]]; then
  PKG_MGR=pacman
  PKGS=(base-devel git curl wget ca-certificates gnupg python python-setuptools
        perl rsync subversion unzip zip file gawk gettext flex bison cpio bc
        ncurses openssl zlib libxslt pkgconf time patch diffutils which
        tar xz zstd elfutils cmake ninja swig autoconf automake libtool texinfo)
  query_pkg() { pacman -Qq "$1" >/dev/null 2>&1; }
elif [[ $OS_ID == ubuntu || $OS_ID == debian || " $OS_ID_LIKE " == *" debian "* ]]; then
  PKG_MGR=apt
  PKGS=(build-essential git curl wget ca-certificates gnupg python3 python3-setuptools
        perl rsync subversion unzip zip file gawk gettext flex bison cpio bc
        libncurses-dev libssl-dev zlib1g-dev libelf-dev libxslt1-dev
        pkg-config time patch diffutils util-linux xz-utils zstd cmake ninja-build swig
        autoconf automake libtool libtool-bin texinfo)
  query_pkg() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed'; }
else
  die "Unsupported distribution (${OS_ID:-unknown}); use Debian, Ubuntu, or Arch"
fi

missing=()
for pkg in "${PKGS[@]}"; do query_pkg "$pkg" || missing+=("$pkg"); done
if ((${#missing[@]})); then
  (( AUTO_DEPS == 1 )) || die "Missing host packages: ${missing[*]}"
  if command -v sudo >/dev/null 2>&1; then SUDO=(sudo); else die 'sudo required to install host dependencies'; fi
  log "Installing ${#missing[@]} missing $PKG_MGR packages: ${missing[*]}"
  if [[ $PKG_MGR == apt ]]; then
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
  else
    # Refresh indexes with a full upgrade so Arch never receives a partial upgrade.
    "${SUDO[@]}" pacman -Syu --noconfirm
    "${SUDO[@]}" pacman -S --needed --noconfirm "${missing[@]}"
  fi
fi
for tool in git curl gpg python3 make sha256sum readelf tar ar flock; do
  command -v "$tool" >/dev/null 2>&1 || die "Missing required command: $tool"
done

mkdir -p -- "$WORKDIR"
WORKDIR=$(cd -- "$WORKDIR" && pwd -P)
exec 9>"$WORKDIR/.build.lock"
flock -n 9 || die "Another build is already running in $WORKDIR"
available_kib=$(df -Pk "$WORKDIR" | awk 'END {print $4}')
if [[ $available_kib =~ ^[0-9]+$ ]] && (( available_kib < 8 * 1024 * 1024 )); then
  log "WARNING: Less than 8 GiB free in workdir filesystem; toolchain build may exhaust disk"
fi
ENTWARE="$WORKDIR/Entware"
DOWNLOAD_DIR="$WORKDIR/source"
mkdir -p -- "$DOWNLOAD_DIR"

ENTWARE_REV=${ENTWARE_REV:-8c851f3c5e8ecf4dbadee96bd425345b424af1c2}
ENTWARE_PACKAGES_REV=${ENTWARE_PACKAGES_REV:-f2728214b8a3109e89dcfa188a3cedcf4edf2e57}

discover_and_fetch_nginx() {
  # Extract a release version from the current official HTML page (not a mirror).
  if [[ -z $VERSION ]]; then
    log "Discovering latest $CHANNEL NGINX release from nginx.org"
    local html_file="$DOWNLOAD_DIR/download.html"
    curl --http1.1 --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
         'https://nginx.org/en/download.html' -o "$html_file"
    VERSION=$(python3 - "$CHANNEL" "$html_file" <<'PY'
import re, sys
channel, filename = sys.argv[1:]
page = open(filename, encoding='utf-8').read()
# The official page has distinct 'Mainline version' and 'Stable version' headings.
m = re.search(r'(?is)\b' + re.escape(channel) +
              r'\s+version\b(?:(?!\b(?:mainline|stable|legacy)\s+version\b).){0,5000}?' +
              r'nginx-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.gz', page)
if not m:
    sys.exit(f'Cannot identify latest {channel} version on nginx.org download page')
print(m.group(1))
PY
    )
  fi
  log "Selected NGINX $VERSION ($RELEASE_SELECTION)"

  # Verify authentic nginx.org sources before touching build recipes.
  TARBALL="$DOWNLOAD_DIR/nginx-$VERSION.tar.gz"
  ASC="$TARBALL.asc"
  for extension in '' .asc; do
    local path="$TARBALL$extension"
    if [[ ! -s $path ]]; then
      log "Downloading $(basename "$path")"
      curl --http1.1 --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
           "https://nginx.org/download/nginx-$VERSION.tar.gz$extension" -o "$path.partial"
      mv -f -- "$path.partial" "$path"
    fi
  done

  GPG_HOME=$(mktemp -d)
  chmod 0700 "$GPG_HOME"
  # Source-signing keys; fingerprints are pinned independently of fetched key files.
  declare -A nginx_keys=(
    [arut]=43387825DDB1BB97EC36BA5D007C8D7C15D87369
    [pluknet]=D6786CE303D9A9022998DC6CC8464D549AF75C0A
    [sb]=7338973069ED3F443F4D37DFA64FD5B17ADB39A8
    [thresh]=13C82A63B603576156E30A4EA0EA981B66B0D967
  )
  for key in arut pluknet sb thresh; do
    local keyfile="$GPG_HOME/$key.key"
    curl --http1.1 --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
         "https://nginx.org/keys/$key.key" -o "$keyfile"
    local actual
    actual=$(GNUPGHOME="$GPG_HOME" gpg --batch --show-keys --with-colons "$keyfile" \
      | awk -F: '$1=="pub" {want=1; next} want && $1=="fpr" {print $10; exit}')
    [[ $actual == "${nginx_keys[$key]}" ]] || die "Unexpected NGINX signing key fingerprint for $key: $actual"
    GNUPGHOME="$GPG_HOME" gpg --batch --quiet --import "$keyfile"
  done
  log 'Verifying NGINX source release signature'
  GNUPGHOME="$GPG_HOME" gpg --batch --verify "$ASC" "$TARBALL" \
    || die 'NGINX source signature verification failed'
  SOURCE_SHA256=$(sha256sum "$TARBALL" | awk '{print $1}')
  log "Verified nginx-$VERSION.tar.gz: $SOURCE_SHA256"
}

# Preserve Entware's complete feed list: packages includes Rust and Go feed files
# even when only NGINX is being built. Repair the single-feed config written by
# older versions before git-pull, since feeds.conf is tracked upstream.
sync_feeds_conf() {
  local upstream_feeds legacy_feed
  upstream_feeds=$(git -C "$ENTWARE" show HEAD:feeds.conf) \
    || die 'Cannot read upstream Entware feeds.conf'
  legacy_feed='src-git packages https://github.com/Entware/entware-packages.git'
  if [[ -n ${ENTWARE_PACKAGES_REV:-} ]]; then
    upstream_feeds=$(sed -E "s#^(src-git packages https://github.com/Entware/entware-packages.git).*#\1^${ENTWARE_PACKAGES_REV}#" <<< "$upstream_feeds")
  fi
  if [[ -e $ENTWARE/feeds.conf ]]; then
    local current_feeds
    current_feeds=$(cat "$ENTWARE/feeds.conf")
    if [[ $current_feeds != "$upstream_feeds" && $current_feeds != "$legacy_feed" ]]; then
      log 'Synchronizing feeds.conf with configured feed revisions'
    fi
  fi
  printf '%s\n' "$upstream_feeds" > "$ENTWARE/feeds.conf"
}

# Obtain Entware build system in an isolated workspace, never in user's repo.
if [[ ! -d $ENTWARE/.git ]]; then
  [[ ! -e $ENTWARE ]] || die "$ENTWARE exists but is not an Entware git checkout"
  log 'Cloning Entware build system'
  git clone https://github.com/Entware/Entware.git "$ENTWARE"
  if [[ -n ${ENTWARE_REV:-} ]]; then
    log "Checking out validated Entware revision $ENTWARE_REV"
    git -C "$ENTWARE" checkout -q "$ENTWARE_REV"
  fi
else
  sync_feeds_conf
  if (( UPDATE_REPOS )); then
    if [[ -z ${ENTWARE_REV:-} ]]; then
      log 'Updating Entware build system (fast-forward only)'
      git -C "$ENTWARE" pull --ff-only
    else
      log "Ensuring Entware is at validated revision $ENTWARE_REV"
      git -C "$ENTWARE" checkout -q "$ENTWARE_REV"
    fi
  fi
fi
[[ -f "$ENTWARE/configs/$ENTWARE_TARGET.config" ]] || die "Entware $ENTWARE_TARGET target config not found"
sync_feeds_conf

log 'Fetching/updating Entware feeds and installing feed symlinks'
if (( UPDATE_REPOS )); then
  (cd "$ENTWARE" && ./scripts/feeds update -a)
else
  # --no-update keeps existing checkouts, but a repaired or fresh workspace may
  # still need feeds that were never cloned by the old single-feed builder.
  while read -r feed_type feed_name feed_url; do
    [[ $feed_type == src-git ]] || continue
    if [[ ! -d $ENTWARE/feeds/$feed_name ]]; then
      (cd "$ENTWARE" && ./scripts/feeds update "$feed_name")
    fi
  done < "$ENTWARE/feeds.conf"
fi
# Re-index after ALL feeds exist, resolving cross-feed includes during scanning.
(cd "$ENTWARE" && make package/symlinks-install)

toolchain_ready() {
  local stamp
  for stamp in "$ENTWARE"/staging_dir/toolchain-*/stamp/.gcc_final_installed; do
    if [[ -f $stamp ]]; then return 0; fi
  done
  return 1
}

TARGET_CONFIG="$ENTWARE/configs/$ENTWARE_TARGET.config"
BASE_HASH=$(sha256sum "$TARGET_CONFIG" | awk '{print $1}')
CONFIG_MARKER="$ENTWARE/.nginx-${ENTWARE_TARGET//./-}-target-config-sha256"

# Phase 1: Toolchain bootstrap using Entware's stock validated target configuration.
if ! toolchain_ready; then
  log 'Cross-toolchain not found; preparing bootstrap configuration'
  cp -f -- "$TARGET_CONFIG" "$ENTWARE/.config"
  # Target config defines the validated bootstrap configuration:
  # CONFIG_PKG_CC_STACKPROTECTOR_NONE=y, CONFIG_PKG_FORTIFY_SOURCE_NONE=y,
  # CONFIG_PKG_RELRO_NONE=y, CONFIG_PKG_ASLR_PIE_NONE=y.
  # Package-level hardening flags must NOT leak into toolchain bootstrap;
  # glibc 2.27 loader fails linking rtld with duplicate symbols when stack-protector is enabled globally.
  (cd "$ENTWARE" && make defconfig)
  printf '%s\n' "$BASE_HASH" > "$CONFIG_MARKER"

  log "Building Entware cross-toolchain with $JOBS jobs (first run can be lengthy)"
  (cd "$ENTWARE" && make -j"$JOBS" tools/install)
  # Linux 3.10 host helpers use identifiers such as constexpr which became C23
  # keywords. Limit GNU C17 to the header bootstrap; retain Entware's cross compiler
  # and normal host flags for the remaining toolchain and packages.
  (cd "$ENTWARE" && make -j"$JOBS" toolchain/kernel-headers/compile V=s \
    HOST_CFLAGS="-O2 -std=gnu17 -I$ENTWARE/staging_dir/host/include" \
    HOST_CXXFLAGS="-O2 -I$ENTWARE/staging_dir/host/include")
  (cd "$ENTWARE" && make -j"$JOBS" toolchain/install V=s MAKEINFO=true ac_cv_prog_MAKEINFO=true)
  # target/compile prepares a separate Linux source tree and rebuilds the same
  # legacy host helpers, so it needs the compatibility flags too.
  (cd "$ENTWARE" && make -j"$JOBS" target/compile V=s \
    HOST_CFLAGS="-O2 -std=gnu17 -I$ENTWARE/staging_dir/host/include" \
    HOST_CXXFLAGS="-O2 -I$ENTWARE/staging_dir/host/include")
else
  log 'Entware cross-toolchain already built and ready'
fi

if (( TOOLCHAIN_ONLY )); then
  log "Entware cross-toolchain and target environment built successfully at $WORKDIR"
  exit 0
fi

# Phase 2: Package build with full hardening profile.
discover_and_fetch_nginx

RECIPE_FILE="$ENTWARE/feeds/packages/net/nginx/Makefile"
[[ -f $RECIPE_FILE ]] || die "Entware nginx recipe not found: $RECIPE_FILE"
[[ -e $ENTWARE/package/feeds/packages/nginx/Makefile ]] || die 'Entware nginx feed symlink is missing'

# Apply the version/hash only temporarily; restore on success or error, so the
# next run can git-pull the upstream Entware package feed cleanly.
# Entware's 'regular' PIE build mode is opt-in per package; explicitly opt in
# nginx-ssl (the same source build also produces the matching Brotli modules).
RECIPE_BACKUP=$(mktemp)
cp -p -- "$RECIPE_FILE" "$RECIPE_BACKUP"
python3 - "$RECIPE_FILE" "$VERSION" "$SOURCE_SHA256" <<'PY'
from pathlib import Path
import re, sys
p, version, digest = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text()
for name, value in [('PKG_VERSION', version), ('PKG_HASH', digest), ('PKG_RELEASE', '99')]:
    pattern = rf'(?m)^({name}:=).*?$'
    s, count = re.subn(pattern, lambda m: m.group(1) + value, s, count=1)
    if count != 1:
        sys.exit(f'Expected exactly one {name} entry in {p}; aborting')
# The Entware hardening policy only applies regular PIE to packages that opt in.
# Do not alter upstream recipe permanently: cleanup restores the original file.
if 'PKG_ASLR_PIE_REGULAR:=' in s:
    s, n = re.subn(r'(?m)^PKG_ASLR_PIE_REGULAR:=.*$',
                   'PKG_ASLR_PIE_REGULAR:=1', s, count=1)
    if n != 1:
        sys.exit('Failed to set PIE opt-in for nginx')
else:
    anchor = 'PKG_BUILD_FLAGS:='
    if anchor not in s:
        sys.exit('Cannot find Entware NGINX PKG_BUILD_FLAGS anchor for PIE opt-in')
    s = s.replace(anchor, 'PKG_ASLR_PIE_REGULAR:=1\n' + anchor, 1)
p.write_text(s)
PY
# Source archive is injected into Entware's download cache, where its SHA-256
# is independently checked by the package build system.
mkdir -p "$ENTWARE/dl"
cp -f -- "$TARBALL" "$ENTWARE/dl/nginx-$VERSION.tar.gz"

# Fixed, broad reverse-proxy profile; not per-build feature switches.
# Apply this on EVERY run, including cached builds, so former minimal profiles
# cannot silently persist.
if [[ ! -f "$ENTWARE/.config" || ! -f $CONFIG_MARKER || $(cat "$CONFIG_MARKER") != "$BASE_HASH" ]]; then
  if [[ -f $ENTWARE/.config && ! -f $CONFIG_MARKER ]]; then
    die 'Existing .config was not created by this script. Use a dedicated --workdir.'
  fi
  log "Initializing Entware $ENTWARE_TARGET config"
  cp -f -- "$TARGET_CONFIG" "$ENTWARE/.config"
fi
log 'Applying reverse-proxy feature and hardening profile'
python3 - "$ENTWARE/.config" <<'PYCONFIG'
from pathlib import Path
import re, sys

path = Path(sys.argv[1])
content = path.read_text()

# Desired Entware package-level hardening. PIE is applied to NGINX explicitly
# via PKG_ASLR_PIE_REGULAR:=1 in its temporary package recipe (not globally).
choices = {
    'PKG_ASLR_PIE': 'REGULAR',
    'PKG_CC_STACKPROTECTOR': 'STRONG',
    'PKG_FORTIFY_SOURCE': '2',
    'PKG_RELRO': 'FULL',
}
settings = {
    'PKG_CHECK_FORMAT_SECURITY': 'y',
    'PACKAGE_nginx-ssl': 'm',
    'PACKAGE_nginx-mod-brotli': 'm',
    # Ship the HTTP modules and the general TCP/UDP stream proxy as matching
    # modules compiled in the SAME NGINX source build.
    'PACKAGE_nginx-mod-stream': 'm',
    'PACKAGE_nginx-mod-headers-more': 'm',
    'PACKAGE_nginx-full': 'n',
    'PACKAGE_nginx-mod-geoip2': 'n',
    'PACKAGE_nginx-mod-lua': 'n',
    'PACKAGE_nginx-mod-lua-resty-core': 'n',
    'PACKAGE_nginx-mod-lua-resty-lrucache': 'n',
    'PACKAGE_nginx-mod-rtmp': 'n',
    'PACKAGE_nginx-mod-dav-ext': 'n',
    'PACKAGE_nginx-mod-naxsi': 'n',
    'PACKAGE_nginx-mod-ts': 'n',
    'PACKAGE_nginx-mod-njs': 'n',
    # Required by the hardened reverse-proxy configuration / TLS.
    'NGINX_HTTP_V2': 'y',
    'NGINX_HTTP_REAL_IP': 'y',
    'NGINX_HTTP_AUTH_REQUEST': 'y',
    'NGINX_HTTP_ACCESS': 'y',
    'NGINX_HTTP_AUTH_BASIC': 'y',
    'NGINX_HTTP_PROXY': 'y',
    'NGINX_HTTP_REWRITE': 'y',
    'NGINX_HTTP_MAP': 'y',
    'NGINX_HTTP_LIMIT_REQ': 'y',
    'NGINX_HTTP_LIMIT_CONN': 'y',
    'NGINX_HTTP_UPSTREAM_KEEPALIVE': 'y',
    'NGINX_HTTP_CACHE': 'y',
    'NGINX_HTTP_GZIP': 'y',
    'NGINX_HTTP_GZIP_STATIC': 'y',
    'NGINX_HTTP_FASTCGI': 'y',
    'NGINX_HTTP_UWSGI': 'y',
    'NGINX_HTTP_SCGI': 'y',
    'NGINX_HTTP_MEMCACHED': 'y',
    'NGINX_HTTP_QUIC': 'y',
    'NGINX_STREAM_REAL_IP': 'y',
    'NGINX_PCRE': 'y',
    # Broad upstream compatibility; omit features that serve or transform
    # local content or add tracking/legacy application-server capability.
    # Keep other useful stock modules (GEO, REFERER, balancing, etc.).
    'NGINX_DAV': 'n',
    'NGINX_FLV': 'n',
    'NGINX_HTTP_SSI': 'n',
    'NGINX_HTTP_USERID': 'n',
    'NGINX_HTTP_AUTOINDEX': 'n',
    'NGINX_HTTP_EMPTY_GIF': 'n',
    'NGINX_HTTP_BROWSER': 'n',
}
for family, chosen in choices.items():
    # All alternatives form one Kconfig choice, so remove all existing states.
    options = {
        'PKG_ASLR_PIE': ['NONE', 'REGULAR', 'ALL'],
        'PKG_CC_STACKPROTECTOR': ['NONE', 'REGULAR', 'STRONG', 'ALL'],
        'PKG_FORTIFY_SOURCE': ['NONE', '1', '2', '3'],
        'PKG_RELRO': ['NONE', 'PARTIAL', 'FULL'],
    }[family]
    for option in options:
        name = f'CONFIG_{family}_{option}'
        settings[f'{family}_{option}'] = 'y' if option == chosen else 'n'

# Exact-line replacement avoids duplicate Kconfig declarations in cached builds.
for name, value in settings.items():
    key = 'CONFIG_' + name
    content = re.sub(
        r'(?m)^(?:' + re.escape(key) + r'=.*|# ' + re.escape(key) + r' is not set)\n?',
        '', content,
    )
    content += (f'{key}={value}\n' if value != 'n'
                else f'# {key} is not set\n')
path.write_text(content)
PYCONFIG
(cd "$ENTWARE" && make defconfig)
printf '%s\n' "$BASE_HASH" > "$CONFIG_MARKER"

# Stop early if feed Kconfig constraints prevented required choices.
# 'n' is represented by the conventional '# CONFIG_... is not set' line.
expect_kconfig() {
  local key=$1 wanted=$2
  if [[ $wanted == n ]]; then
    grep -Fqx "# CONFIG_$key is not set" "$ENTWARE/.config" \
      || die "Feature CONFIG_$key must be disabled; check Entware Kconfig dependencies"
  else
    grep -Fqx "CONFIG_$key=$wanted" "$ENTWARE/.config" \
      || die "Feature CONFIG_$key=$wanted was not selected by Entware Kconfig"
  fi
}
for name in PKG_ASLR_PIE_REGULAR PKG_CC_STACKPROTECTOR_STRONG \
  PKG_FORTIFY_SOURCE_2 PKG_RELRO_FULL PKG_CHECK_FORMAT_SECURITY \
  NGINX_HTTP_V2 NGINX_HTTP_QUIC NGINX_HTTP_REAL_IP NGINX_HTTP_AUTH_REQUEST \
  NGINX_HTTP_ACCESS NGINX_HTTP_AUTH_BASIC NGINX_HTTP_PROXY \
  NGINX_HTTP_REWRITE NGINX_HTTP_MAP NGINX_HTTP_LIMIT_REQ NGINX_HTTP_LIMIT_CONN \
  NGINX_HTTP_UPSTREAM_KEEPALIVE NGINX_HTTP_CACHE NGINX_HTTP_GZIP \
  NGINX_HTTP_GZIP_STATIC NGINX_HTTP_FASTCGI NGINX_HTTP_UWSGI \
  NGINX_HTTP_SCGI NGINX_HTTP_MEMCACHED NGINX_STREAM_REAL_IP NGINX_PCRE; do
  expect_kconfig "$name" y
done
for name in PKG_FORTIFY_SOURCE_NONE PKG_FORTIFY_SOURCE_1 PKG_FORTIFY_SOURCE_3 \
  NGINX_DAV NGINX_FLV NGINX_HTTP_SSI NGINX_HTTP_USERID \
  NGINX_HTTP_AUTOINDEX NGINX_HTTP_EMPTY_GIF NGINX_HTTP_BROWSER \
  PACKAGE_nginx-full PACKAGE_nginx-mod-geoip2 PACKAGE_nginx-mod-lua \
  PACKAGE_nginx-mod-lua-resty-core PACKAGE_nginx-mod-lua-resty-lrucache \
  PACKAGE_nginx-mod-rtmp PACKAGE_nginx-mod-dav-ext PACKAGE_nginx-mod-naxsi \
  PACKAGE_nginx-mod-ts PACKAGE_nginx-mod-njs; do
  expect_kconfig "$name" n
done
for name in nginx-ssl nginx-mod-brotli nginx-mod-stream nginx-mod-headers-more; do
  expect_kconfig "PACKAGE_$name" m
done

# The pinned Entware AArch64 target is already speed-oriented; do not
# replace -O2 with size optimization or disable package-level LTO/hardening.
if [[ "$ENTWARE_TARGET" == aarch64-3.10 ]]; then
  expect_kconfig TARGET_OPTIMIZATION '"-O2 -pipe -mcpu=cortex-a53"'
  expect_kconfig USE_STRIP y
  grep -Eq '^PKG_BUILD_FLAGS:=[[:space:]]*gc-sections[[:space:]]+lto([[:space:]]|$)' "$RECIPE_FILE" \
    || die 'Expected nginx package-level section GC and LTO'
fi

log "Compiling NGINX, Brotli, stream and headers-more with $JOBS jobs"
# Do not reuse a package compilation for a previous NGINX release.
(cd "$ENTWARE" && make package/nginx/clean)
(cd "$ENTWARE" && make -j"$JOBS" package/nginx/compile V=s)

# Export NGINX and all three matching dynamic-module packages. We require
# exactly one version-matched IPK per package; never reuse stale modules.
shopt -s nullglob
packages=("$ENTWARE"/bin/targets/"$ENTWARE_TARGET"/*/packages/nginx-ssl_"$VERSION"-*.ipk)
brotli_packages=("$ENTWARE"/bin/targets/"$ENTWARE_TARGET"/*/packages/nginx-mod-brotli_"$VERSION"-*.ipk)
stream_packages=("$ENTWARE"/bin/targets/"$ENTWARE_TARGET"/*/packages/nginx-mod-stream_"$VERSION"-*.ipk)
headers_packages=("$ENTWARE"/bin/targets/"$ENTWARE_TARGET"/*/packages/nginx-mod-headers-more_"$VERSION"-*.ipk)
shopt -u nullglob
((${#packages[@]} == 1)) || die "Expected one nginx-ssl $VERSION IPK, found ${#packages[@]}"
((${#brotli_packages[@]} == 1)) || die "Expected one nginx-mod-brotli $VERSION IPK, found ${#brotli_packages[@]}"
((${#stream_packages[@]} == 1)) || die "Expected one nginx-mod-stream $VERSION IPK, found ${#stream_packages[@]}"
((${#headers_packages[@]} == 1)) || die "Expected one nginx-mod-headers-more $VERSION IPK, found ${#headers_packages[@]}"
IPK=${packages[0]}
BROTLI_IPK=${brotli_packages[0]}
STREAM_IPK=${stream_packages[0]}
HEADERS_IPK=${headers_packages[0]}
if [[ -z $OUTPUT_DIR ]]; then OUTPUT_DIR="$WORKDIR/out/nginx-$VERSION-$PACKAGE_TARGET"; fi
[[ $OUTPUT_DIR == /* ]] || OUTPUT_DIR="$PWD/$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd -P)
cp -f -- "$IPK" "$BROTLI_IPK" "$STREAM_IPK" "$HEADERS_IPK" "$OUTPUT_DIR/"

# Entware .ipk files may use gzip-wrapped tar or ar for the outer container.
# Extract NGINX and all three module packages into separate staging directories.
extract_ipk() {
  local ipk=$1 dest=$2 data_member
  mkdir -p -- "$dest"
  if ar t "$ipk" >/dev/null 2>&1; then
    data_member=$(ar t "$ipk" | grep -E '^data\.tar\.(gz|xz|zst)$' | head -n1 || true)
    [[ -n $data_member ]] || die "No data.tar payload in $ipk"
    ar p "$ipk" "$data_member" > "$dest/$data_member"
  else
    data_member=$(tar -tzf "$ipk" | sed 's#^\./##' | grep -E '^data\.tar\.(gz|xz|zst)$' | head -n1 || true)
    [[ -n $data_member ]] || die "No data.tar payload in $ipk"
    tar -xOf "$ipk" "./$data_member" > "$dest/$data_member" \
      || tar -xOf "$ipk" "$data_member" > "$dest/$data_member"
  fi
  mkdir -p "$dest/root"
  tar -xf "$dest/$data_member" -C "$dest/root"
}
STAGE_DIR=$(mktemp -d)
extract_ipk "$IPK" "$STAGE_DIR/nginx"
extract_ipk "$BROTLI_IPK" "$STAGE_DIR/brotli"
extract_ipk "$STREAM_IPK" "$STAGE_DIR/stream"
extract_ipk "$HEADERS_IPK" "$STAGE_DIR/headers"
[[ -f $STAGE_DIR/nginx/root/opt/sbin/nginx ]] || die 'No /opt/sbin/nginx in compiled IPK'
install -m 0755 "$STAGE_DIR/nginx/root/opt/sbin/nginx" "$OUTPUT_DIR/nginx"
# Map each module to the package it came from to prevent a mismatched export.
module_sources=(
  'brotli:ngx_http_brotli_filter_module.so'
  'brotli:ngx_http_brotli_static_module.so'
  'stream:ngx_stream_module.so'
  'headers:ngx_http_headers_more_filter_module.so'
)
for entry in "${module_sources[@]}"; do
  package_dir=${entry%%:*}
  module=${entry#*:}
  module_path="$STAGE_DIR/$package_dir/root/opt/lib/nginx/modules/$module"
  [[ -f $module_path ]] || die "Missing module from newly built package: $module_path"
  install -m 0755 "$module_path" "$OUTPUT_DIR/$module"
  readelf -h "$OUTPUT_DIR/$module" | grep -Eq "Machine:.*$EXPECTED_MACHINE([[:space:]]|$)" || die "$module is not a $EXPECTED_MACHINE ELF"
done
rm -rf -- "$STAGE_DIR"
STAGE_DIR=

readelf -h "$OUTPUT_DIR/nginx" | grep -Eq "Machine:.*$EXPECTED_MACHINE([[:space:]]|$)" || die "Output is not a $EXPECTED_MACHINE ELF executable"
# Nginx is a network-exposed service: fail if the security build settings did
# not actually result in a PIE executable with non-executable stack and full
# RELRO. Shared modules must also have a non-executable stack and full RELRO.
verify_elf_hardening() {
  local binary=$1 label=$2 e_type program_headers dynamic_section stack_line
  e_type=$(readelf -hW "$binary" | awk '/Type:/ {print $2; exit}')
  if [[ $label == nginx ]]; then
    [[ $e_type == DYN ]] || die "NGINX missing PIE (ELF type $e_type; expected DYN)"
    readelf -lW "$binary" | grep -Fq 'Requesting program interpreter:' \
      || die 'Nginx PIE missing PT_INTERP segment'
  fi
  program_headers=$(readelf -lW "$binary")
  grep -Eq '(^|[[:space:]])GNU_RELRO([[:space:]]|$)' <<< "$program_headers" \
    || die "$label missing GNU_RELRO"
  stack_line=$(grep -E '^[[:space:]]*GNU_STACK[[:space:]]' <<< "$program_headers" | head -n 1)
  [[ -n $stack_line ]] || die "$label missing GNU_STACK program header"
  ! grep -Eq "[[:space:]]RWE([[:space:]]|$)" <<< "$stack_line" \
    || die "$label has an executable stack"
  dynamic_section=$(readelf -dW "$binary")
  if ! grep -Eq '\((BIND_NOW|FLAGS|FLAGS_1)\).*\b(NOW|BIND_NOW)\b' <<< "$dynamic_section"; then
    die "$label missing immediate binding (-z now; full RELRO)"
  fi
}
verify_elf_hardening "$OUTPUT_DIR/nginx" nginx
for entry in "${module_sources[@]}"; do
  module=${entry#*:}
  verify_elf_hardening "$OUTPUT_DIR/$module" "$module"
done
# A generic modern ARM64 binary can have newer glibc requirements than Entware.
python3 - "$OUTPUT_DIR/nginx" \
  "$OUTPUT_DIR/ngx_http_brotli_filter_module.so" \
  "$OUTPUT_DIR/ngx_http_brotli_static_module.so" \
  "$OUTPUT_DIR/ngx_stream_module.so" \
  "$OUTPUT_DIR/ngx_http_headers_more_filter_module.so" <<'PY'
import re, subprocess, sys
for file in sys.argv[1:]:
    s = subprocess.check_output(['readelf', '--version-info', file], text=True)
    needed = sorted(set(tuple(map(int, x.split('.'))) for x in re.findall(r'GLIBC_([0-9]+\.[0-9]+)', s)))
    if needed and needed[-1] > (2, 27):
        sys.exit(f'{file} requires GLIBC_{needed[-1][0]}.{needed[-1][1]} > Entware glibc 2.27')
    print(file, 'maximum required glibc:', '.'.join(map(str, needed[-1])) if needed else '(none in version section)')
PY
(
  cd "$OUTPUT_DIR"
  sha256sum nginx \
    ngx_http_brotli_filter_module.so ngx_http_brotli_static_module.so \
    ngx_stream_module.so ngx_http_headers_more_filter_module.so \
    "${IPK##*/}" "${BROTLI_IPK##*/}" "${STREAM_IPK##*/}" "${HEADERS_IPK##*/}" \
    > SHA256SUMS
  {
    printf 'nginx_version=%s\n' "$VERSION"
    printf 'release_selection=%s\n' "$RELEASE_SELECTION"
    printf 'target=%s\n' "$PACKAGE_TARGET"
    printf 'nginx_source_sha256=%s\n' "$SOURCE_SHA256"
    printf 'profile=toolbox-reverse-proxy-hardened-v2-broad-upstream\n'
    printf 'hardening=PIE+SSP_STRONG+FORTIFY2+FULL_RELRO+FORMAT_SECURITY\n'
    grep -E '^CONFIG_(TARGET_OPTIMIZATION|STRIP_ARGS)=' "$ENTWARE/.config"
    grep -E '^PKG_BUILD_FLAGS:=' "$RECIPE_FILE"
    printf 'nginx_binary_bytes=%s\n' "$(wc -c < nginx)"
    printf 'enabled_upstreams=HTTP,HTTPS,GRPC,FASTCGI,UWSGI,SCGI,MEMCACHED,TCP,UDP\n'
    printf 'enabled_features=HTTP2,HTTP3,REAL_IP,ACCESS,AUTH_REQUEST,RATE_LIMIT,CONN_LIMIT,GZIP,BROTLI,HEADERS_MORE\n'
    printf 'disabled_modules=DAV,FLV,SSI,USERID,AUTOINDEX,EMPTY_GIF,BROWSER,NJS,GEOIP2,NAXSI,LUA,RTMP,TS,DAV_EXT\n'
    printf '\nSelected configuration:\n'
    grep -E '^(CONFIG_PKG_(ASLR_PIE_REGULAR|CC_STACKPROTECTOR_STRONG|FORTIFY_SOURCE_2|RELRO_FULL|CHECK_FORMAT_SECURITY)=y|CONFIG_NGINX_HTTP_(V2|REAL_IP|QUIC|AUTH_REQUEST|FASTCGI|UWSGI|SCGI|MEMCACHED)=y|CONFIG_PACKAGE_nginx-(ssl|mod-(brotli|stream|headers-more))=m)' "$ENTWARE/.config"
    printf 'entware_commit=%s\n' "$(git -C "$ENTWARE" rev-parse HEAD)"
    printf 'entware_packages_commit=%s\n' "$(git -C "$ENTWARE/feeds/packages" rev-parse HEAD)"
    printf '\nELF interpreter:\n'
    readelf -l nginx | grep 'Requesting program interpreter' || true
    for f in nginx ngx_http_brotli_filter_module.so ngx_http_brotli_static_module.so \
      ngx_stream_module.so ngx_http_headers_more_filter_module.so; do
      printf '\nELF shared library dependencies for %s:\n' "$f"
      readelf -d "$f" | grep '(NEEDED)' || true
    done
  } > build-info.txt
)
log "Build complete: $OUTPUT_DIR/nginx"
log "Entware packages: nginx-ssl, nginx-mod-brotli, nginx-mod-stream, nginx-mod-headers-more"
log 'Matching Brotli, stream and headers-more .so modules exported alongside nginx'
log 'Nothing was installed on your router. Test the binary and nginx -t before replacing any running service.'
