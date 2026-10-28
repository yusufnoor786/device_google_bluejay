#!/usr/bin/env bash
# Put the KernelSU-Next patch step INSIDE the ROM's build_kernel() (vendor/*/build/envsetup.sh), right after it
# prints "Kernel build output copied to ...". build_kernel is what `lunch` runs to build the kernel and to wipe +
# refill device/google/bluejay-kernels/6.1, so hooking there does not depend on shell wrappers or vendorsetup.sh.
#
# usage (from the ROM source root, or with ANDROID_BUILD_TOP set):
#   device/google/bluejay/ksu-kernel/install-build-hook.sh            install (idempotent)
#   device/google/bluejay/ksu-kernel/install-build-hook.sh --remove   undo
#   device/google/bluejay/ksu-kernel/install-build-hook.sh --status   show where it is installed
# Afterwards re-source the environment:  source build/envsetup.sh
set -uo pipefail

TOP=${ANDROID_BUILD_TOP:-$PWD}
MODE=${1:-install}
MARK='# KSU-Next hook (device/google/bluejay/ksu-kernel/install-build-hook.sh)'

# the definitions of build_kernel live in a few envsetup.sh files; look only in the usual places
mapfile -t FILES < <(find "$TOP/vendor" "$TOP/build" -maxdepth 4 -name envsetup.sh 2>/dev/null | xargs -r grep -l 'Kernel build output copied to' 2>/dev/null)
if [ ${#FILES[@]} -eq 0 ]; then
  echo "[ksu-kernel] ERROR: no envsetup.sh with build_kernel() found under $TOP/vendor or $TOP/build" >&2; exit 1
fi

for f in "${FILES[@]}"; do
  case $MODE in
    --status) if grep -qF "$MARK" "$f"; then echo "installed:     $f"; else echo "not installed: $f"; fi ;;
    --remove)
      if grep -qF "$MARK" "$f"; then
        python3 - "$f" "$MARK" <<'PY'
import sys
p, mark = sys.argv[1], sys.argv[2]
lines = open(p).read().split("\n")
out, i = [], 0
while i < len(lines):
    if lines[i].strip() == mark:
        # drop the blank line we added before the marker, the marker line and the if...fi block after it
        if out and out[-1].strip() == "":
            out.pop()
        i += 1
        while i < len(lines) and lines[i].strip() != "fi":
            i += 1
        i += 1
        continue
    out.append(lines[i]); i += 1
open(p, "w").write("\n".join(out))
PY
        echo "removed from $f"
      else echo "not present in $f"; fi ;;
    install|*)
      if grep -qF "$MARK" "$f"; then echo "already installed in $f"; continue; fi
      python3 - "$f" "$MARK" <<'PY' || { echo "[ksu-kernel] ERROR: could not patch $f (unexpected build_kernel layout)" >&2; exit 1; }
import re, sys
p, mark = sys.argv[1], sys.argv[2]
s = open(p).read()
anchor = re.compile(r'(\n[ \t]*echo "Kernel build output copied to [^\n]*\n)(\}\n)')
if not anchor.search(s):
    sys.exit(1)
hook = (r'''\1
    ''' + mark + r'''
    if [ "${target_kernel_device}" = "bluejay" ] && [ -x "${ANDROID_BUILD_TOP}/device/google/bluejay/ksu-kernel/patch-kernel.sh" ]; then
        ANDROID_BUILD_TOP="${ANDROID_BUILD_TOP}" "${ANDROID_BUILD_TOP}/device/google/bluejay/ksu-kernel/patch-kernel.sh" \
            || echo "[ksu-kernel] WARNING: patching failed, the ROM will NOT contain KernelSU-Next (run ksu_kernel_patch)" >&2
    fi
\2''')
open(p, "w").write(anchor.sub(lambda m: m.group(1) + "\n    " + mark + '\n    if [ "${target_kernel_device}" = "bluejay" ] && [ -x "${ANDROID_BUILD_TOP}/device/google/bluejay/ksu-kernel/patch-kernel.sh" ]; then\n        ANDROID_BUILD_TOP="${ANDROID_BUILD_TOP}" "${ANDROID_BUILD_TOP}/device/google/bluejay/ksu-kernel/patch-kernel.sh" \\\n            || echo "[ksu-kernel] WARNING: patching failed, the ROM will NOT contain KernelSU-Next (run ksu_kernel_patch)" >&2\n    fi\n' + m.group(2), s, count=1))
PY
      echo "installed in $f" ;;
  esac
done
[ "$MODE" = --status ] || echo "[ksu-kernel] now re-source the environment: source build/envsetup.sh"
