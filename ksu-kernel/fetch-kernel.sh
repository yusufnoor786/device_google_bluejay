#!/usr/bin/env bash
# Fetch the KernelSU-Next patched bluejay kernel (boot.img, modules, dtbs, ...) from the
# GitHub release built by yusufnoor786/bluejay-ksu-kernel-ci into the prebuilt kernel dir.
# Called from device-bluejay.mk, i.e. at lunch / build-config time. All logs go to stderr.
#
# usage: fetch-kernel.sh <dest_dir>
# env:   KSU_KERNEL_REPO      GitHub repo with the releases   (default below)
#        KSU_KERNEL_TAG       pin a release tag               (default: latest)
#        KSU_KERNEL_LOCAL_DIR dir holding bluejay-kernel-ksu.tar.gz[.sha256] (offline / testing)
#        KSU_KERNEL_SKIP=1    do nothing (use whatever is already in <dest_dir>)
#        KSU_KERNEL_OFFLINE=1 never touch the network; only check that <dest_dir> has a kernel.
#                             Used by device-bluejay.mk: the Android build (soong_ui) forbids curl/wget.
set -uo pipefail

DEST=${1:?dest dir}
REPO=${KSU_KERNEL_REPO:-yusufnoor786/bluejay-ksu-kernel-ci}
ASSET=bluejay-kernel-ksu.tar.gz
STAMP="$DEST/.ksu-kernel-release"

log() { echo "[ksu-kernel] $*" >&2; }
# The Android build puts its own prebuilt python3 (no CA certificates) first on PATH, so for the
# python fallback prefer the system python and load the system CA bundle. TLS verification is
# never turned off (the tarball is also sha256-checked).
pick_python() {
  local p
  for p in /usr/bin/python3 /usr/local/bin/python3; do [ -x "$p" ] && { echo "$p"; return; }; done
  command -v python3
}

# download <url> <out>: curl, else wget, else python3.  KSU_DL_TOOL=curl|wget|python forces one.
dl() {
  local url=$1 out=$2 tool=${KSU_DL_TOOL:-}
  if [ -z "$tool" ]; then
    if command -v curl >/dev/null 2>&1; then tool=curl
    elif command -v wget >/dev/null 2>&1; then tool=wget
    else tool=python; fi
  fi
  case $tool in
    curl)   curl -fsSL --retry 3 --max-time 600 -o "$out" "$url" ;;
    wget)   wget -q -t 3 -T 60 -O "$out" "$url" ;;
    python) "$(pick_python)" - "$url" "$out" <<'PY'
import os, ssl, sys, urllib.request

CANDIDATES = [os.environ.get("SSL_CERT_FILE", ""),
              "/etc/ssl/certs/ca-certificates.crt",   # Debian/Ubuntu
              "/etc/pki/tls/certs/ca-bundle.crt",     # RHEL/Fedora
              "/etc/ssl/ca-bundle.pem",               # openSUSE
              "/etc/ssl/cert.pem"]                    # Alpine/macOS
ctx = ssl.create_default_context()
if not ctx.cert_store_stats().get("x509_ca"):
    for c in CANDIDATES:
        if c and os.path.isfile(c) and os.path.getsize(c) > 0:
            ctx = ssl.create_default_context(cafile=c)
            break
req = urllib.request.Request(sys.argv[1], headers={"User-Agent": "ksu-kernel-fetch"})
try:
    with urllib.request.urlopen(req, timeout=120, context=ctx) as r, open(sys.argv[2], "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
except Exception as e:
    sys.exit("download failed: %s (install curl or ca-certificates, or set SSL_CERT_FILE)" % e)
PY
    ;;
  esac
}
have_kernel() { [ -f "$DEST/boot.img" ] && ls "$DEST"/*.ko >/dev/null 2>&1; }
# the files in DEST must come from a KSU release (stamp file), otherwise KernelSU is NOT in the kernel
warn_unstamped() {
  [ -f "$STAMP" ] && return 0
  log "WARNING: the kernel files in $DEST were NOT installed from a KernelSU-Next release (no $(basename "$STAMP"))."
  log "WARNING: boot.img there is probably an unpatched kernel, so KernelSU-Next will NOT work. Run: ksu_kernel_update"
}

if [ "${KSU_KERNEL_SKIP:-0}" = 1 ]; then log "skipped (KSU_KERNEL_SKIP=1)"; exit 0; fi
if [ ! -d "$DEST" ]; then log "ERROR: $DEST does not exist (is device/google/bluejay-kernels synced?)"; exit 1; fi

if [ "${KSU_KERNEL_OFFLINE:-0}" = 1 ]; then
  if have_kernel; then warn_unstamped; log "using kernel in $DEST ($(cat "$STAMP" 2>/dev/null || echo unknown release))"; exit 0; fi
  log "ERROR: no kernel in $DEST. Run: ksu_kernel_update   (or re-run: source build/envsetup.sh)"
  exit 1
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ -n "${KSU_KERNEL_LOCAL_DIR:-}" ]; then
  TAG="local-$(sha256sum "$KSU_KERNEL_LOCAL_DIR/$ASSET" | cut -c1-12)"
  cp "$KSU_KERNEL_LOCAL_DIR/$ASSET" "$KSU_KERNEL_LOCAL_DIR/$ASSET.sha256" "$TMP/" || { log "ERROR: local files missing"; exit 1; }
else
  if [ -n "${KSU_KERNEL_TAG:-}" ]; then API="https://api.github.com/repos/$REPO/releases/tags/$KSU_KERNEL_TAG"
  else API="https://api.github.com/repos/$REPO/releases/latest"; fi
  if ! dl "$API" "$TMP/release.json"; then
    if have_kernel; then log "WARNING: cannot reach GitHub, using existing kernel files in $DEST"; warn_unstamped; exit 0; fi
    log "ERROR: cannot reach $API and $DEST has no kernel files"; exit 1
  fi
  read -r TAG URL SHAURL < <(python3 - "$TMP/release.json" "$ASSET" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); a = {x["name"]: x["browser_download_url"] for x in r["assets"]}
n = sys.argv[2]
print(r["tag_name"], a.get(n, "-"), a.get(n + ".sha256", "-"))
PY
)
  if [ "${URL:--}" = "-" ] || [ "${SHAURL:--}" = "-" ]; then log "ERROR: release $TAG has no $ASSET(.sha256)"; exit 1; fi
fi

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$TAG" ] && have_kernel; then
  log "up to date ($TAG)"; exit 0
fi

log "fetching kernel release $TAG"
if [ -z "${KSU_KERNEL_LOCAL_DIR:-}" ]; then
  dl "$URL" "$TMP/$ASSET" || { log "ERROR: download failed"; exit 1; }
  dl "$SHAURL" "$TMP/$ASSET.sha256" || { log "ERROR: checksum download failed"; exit 1; }
fi

( cd "$TMP" && sha256sum -c "$ASSET.sha256" >&2 ) || { log "ERROR: checksum mismatch, not installing"; exit 1; }

# extract to a temp dir first; only touch the kernel dir once the archive is known good
mkdir -p "$TMP/x"
tar -xzf "$TMP/$ASSET" -C "$TMP/x" || { log "ERROR: extract failed, existing files left untouched"; exit 1; }
[ -f "$TMP/x/boot.img" ] || { log "ERROR: archive has no boot.img, existing files left untouched"; exit 1; }
# replace only the generated binaries (they are .gitignored); keep Lineage's tracked text lists
find "$DEST" -maxdepth 1 -type f \( -name '*.ko' -o -name '*.img' -o -name '*.dtb' -o -name '*.dtbo' \) -delete
cp -p "$TMP"/x/* "$DEST"/ || { log "ERROR: copy into $DEST failed"; exit 1; }
echo "$TAG" > "$STAMP"
log "installed $TAG into $DEST ($(ls "$DEST"/*.ko | wc -l) modules)"
