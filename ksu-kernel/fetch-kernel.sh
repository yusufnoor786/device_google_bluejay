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
set -uo pipefail

DEST=${1:?dest dir}
REPO=${KSU_KERNEL_REPO:-yusufnoor786/bluejay-ksu-kernel-ci}
ASSET=bluejay-kernel-ksu.tar.gz
STAMP="$DEST/.ksu-kernel-release"

log() { echo "[ksu-kernel] $*" >&2; }
have_kernel() { [ -f "$DEST/boot.img" ] && ls "$DEST"/*.ko >/dev/null 2>&1; }

if [ "${KSU_KERNEL_SKIP:-0}" = 1 ]; then log "skipped (KSU_KERNEL_SKIP=1)"; exit 0; fi
if [ ! -d "$DEST" ]; then log "ERROR: $DEST does not exist (is device/google/bluejay-kernels synced?)"; exit 1; fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ -n "${KSU_KERNEL_LOCAL_DIR:-}" ]; then
  TAG="local-$(sha256sum "$KSU_KERNEL_LOCAL_DIR/$ASSET" | cut -c1-12)"
  cp "$KSU_KERNEL_LOCAL_DIR/$ASSET" "$KSU_KERNEL_LOCAL_DIR/$ASSET.sha256" "$TMP/" || { log "ERROR: local files missing"; exit 1; }
else
  if [ -n "${KSU_KERNEL_TAG:-}" ]; then API="https://api.github.com/repos/$REPO/releases/tags/$KSU_KERNEL_TAG"
  else API="https://api.github.com/repos/$REPO/releases/latest"; fi
  if ! curl -fsSL --retry 2 --max-time 60 -o "$TMP/release.json" "$API"; then
    if have_kernel; then log "WARNING: cannot reach GitHub, using existing kernel files in $DEST"; exit 0; fi
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
  curl -fL --retry 3 -o "$TMP/$ASSET" "$URL" >&2 || { log "ERROR: download failed"; exit 1; }
  curl -fsSL --retry 3 -o "$TMP/$ASSET.sha256" "$SHAURL" || { log "ERROR: checksum download failed"; exit 1; }
fi

( cd "$TMP" && sha256sum -c "$ASSET.sha256" >&2 ) || { log "ERROR: checksum mismatch, not installing"; exit 1; }

# replace only the generated binaries (they are .gitignored); keep Lineage's tracked text lists
find "$DEST" -maxdepth 1 -type f \( -name '*.ko' -o -name '*.img' -o -name '*.dtb' -o -name '*.dtbo' \) -delete
tar -xzf "$TMP/$ASSET" -C "$DEST" || { log "ERROR: extract failed"; exit 1; }
echo "$TAG" > "$STAMP"
log "installed $TAG into $DEST ($(ls "$DEST"/*.ko | wc -l) modules)"
