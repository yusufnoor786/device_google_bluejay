#!/usr/bin/env bash
# Patch the kernel that Lineage's build_kernel() just built with KernelSU-Next (LKM, v3.4.2).
#
# build_kernel (vendor/lineage/build/envsetup.sh, called by `lunch`) syncs the Lineage kernel manifest into
# out-kernel/google/gs-6.1, builds it, WIPES device/google/bluejay-kernels/6.1 and copies the unpatched dist
# there. This script then (1) adds the KernelSU-Next module sources to that same kernel workspace,
# (2) builds kernelsu.ko against it, and (3) patches boot.img with ksud, so module and kernel always match.
#
# env: ANDROID_BUILD_TOP  ROM source root (default: current dir)
#      KSU_SKIP=1         do nothing
#      KSU_FORCE=1        patch again even if already patched
#      overrides (testing): KSU_KB (kernel workspace) KSU_DIST (unpatched dist) KSU_DEST (prebuilt dir) KSUD
set -uo pipefail

TOP=${ANDROID_BUILD_TOP:-$PWD}
KB=${KSU_KB:-$TOP/out-kernel/google/gs-6.1}
DIST=${KSU_DIST:-$KB/out/bluejay/dist}
DEST=${KSU_DEST:-$TOP/device/google/bluejay-kernels/6.1}
STAMP=$DEST/.ksu-kernel-release
OWNER=${KSU_OWNER:-yusufnoor786}
MOD_BRANCH=${KSU_MOD_BRANCH:-lineage-24.0}
KSUD_URL=https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.4.2/ksud-x86_64-unknown-linux-musl
KSUD_SHA256=4d22f89416e7eef8f684f1ed03d2bea19da33c7d41266546e94fd7d1f6cbeca9
KSUD_CACHE=$TOP/out-kernel/.ksu/ksud

log() { echo "[ksu-kernel] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

[ "${KSU_SKIP:-0}" = 1 ] && { log "skipped (KSU_SKIP=1)"; exit 0; }
[ -f "$DIST/boot.img" ] || die "no unpatched kernel build at $DIST/boot.img (did lunch build the kernel? SKIP_KERNEL_BUILD?)"
[ -d "$DEST" ] || die "$DEST does not exist"
command -v git >/dev/null || die "git is required"

SRC_ID=$(sha256sum "$DIST/boot.img" | cut -c1-12)
WANT="ksu-v3.4.2-$SRC_ID"
# stamp = line 1: what was patched, line 2: sha256 of the patched boot.img; trust it only if boot.img still matches
if [ "${KSU_FORCE:-0}" != 1 ] && [ -f "$STAMP" ] && [ -f "$DEST/boot.img" ] \
   && [ "$(sed -n 1p "$STAMP")" = "$WANT" ] && [ "$(sed -n 2p "$STAMP")" = "$(sha256sum "$DEST/boot.img" | cut -d' ' -f1)" ]; then
  log "boot.img already KernelSU-patched ($WANT)"; exit 0
fi

# download <url> <out>: curl, wget, or python3 with the system CA bundle (TLS verification stays on)
dl() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -t 3 -O "$2" "$1"
  else
    local py=python3; [ -x /usr/bin/python3 ] && py=/usr/bin/python3
    "$py" - "$1" "$2" <<'PY'
import os, ssl, sys, urllib.request
ctx = ssl.create_default_context()
if not ctx.cert_store_stats().get("x509_ca"):
    for c in (os.environ.get("SSL_CERT_FILE", ""), "/etc/ssl/certs/ca-certificates.crt",
              "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/ca-bundle.pem", "/etc/ssl/cert.pem"):
        if c and os.path.isfile(c) and os.path.getsize(c) > 0:
            ctx = ssl.create_default_context(cafile=c); break
req = urllib.request.Request(sys.argv[1], headers={"User-Agent": "ksu-kernel"})
open(sys.argv[2], "wb").write(urllib.request.urlopen(req, timeout=120, context=ctx).read())
PY
  fi
}

# 1) module sources into the kernel workspace (kept out of Lineage's manifest, so repo sync leaves them alone)
for m in kernelsu susfs; do
  D=$KB/private/google-modules/$m
  if [ -d "$D/.git" ]; then
    [ "${KSU_UPDATE:-0}" = 1 ] && git -C "$D" pull -q --ff-only >&2
  elif [ -d "$D" ] && [ -f "$D/BUILD.bazel" ]; then
    :   # already provided (e.g. by a manifest)
  else
    log "cloning $m module sources"
    git clone -q --depth=1 -b "$MOD_BRANCH" "https://github.com/$OWNER/android_kernel_google_gs-6.1_$m.git" "$D" || die "clone of $m failed"
  fi
done

# 2) build kernelsu.ko in the same Bazel workspace
log "building kernelsu.ko"
( cd "$KB" && tools/bazel build --config=bluejay //private/google-modules/kernelsu:kernelsu >&2 ) || die "kernelsu.ko build failed"
KO=$(find -L "$KB/bazel-bin/private/google-modules/kernelsu" -name kernelsu.ko 2>/dev/null | head -1)
[ -n "$KO" ] && [ -f "$KO" ] || die "kernelsu.ko not found after build"

# 3) ksud (pinned checksum)
KSUD=${KSUD:-$KSUD_CACHE}
if [ ! -x "$KSUD" ]; then
  mkdir -p "$(dirname "$KSUD_CACHE")"
  log "downloading ksud v3.4.2"
  dl "$KSUD_URL" "$KSUD_CACHE.tmp" || { rm -f "$KSUD_CACHE.tmp"; die "ksud download failed (install curl/ca-certificates, or set KSUD=/path/to/ksud)"; }
  echo "$KSUD_SHA256  $KSUD_CACHE.tmp" | sha256sum -c - >&2 || { rm -f "$KSUD_CACHE.tmp"; die "ksud checksum mismatch"; }
  chmod +x "$KSUD_CACHE.tmp" && mv "$KSUD_CACHE.tmp" "$KSUD_CACHE"
fi

# 4) patch the freshly built boot.img and replace the one build_kernel copied
log "patching boot.img"
"$KSUD" boot-patch-v2 --boot "$DIST/boot.img" --module "$KO" --output "$DEST/boot.img.ksu" --force >&2 || { rm -f "$DEST/boot.img.ksu"; die "ksud boot-patch-v2 failed"; }
mv -f "$DEST/boot.img.ksu" "$DEST/boot.img"
{ echo "$WANT"; sha256sum "$DEST/boot.img" | cut -d' ' -f1; } > "$STAMP"
log "boot.img patched with KernelSU-Next ($WANT)"
