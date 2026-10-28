# Sourced by build/envsetup.sh (device/*/*/vendorsetup.sh), i.e. in your normal shell where curl works.
# The Android build (soong_ui/kati) blocks curl/wget, so the kernel download happens here, not in the
# makefiles. device-bluejay.mk then only checks that the files are present.
#
#   ksu_kernel_update            download/refresh the KernelSU-Next kernel now
#   KSU_KERNEL_SKIP=1            do nothing        KSU_KERNEL_TAG=<tag>   pin a release

ksu_kernel_update() {
    local top
    top=$(gettop 2>/dev/null) || top=$PWD
    [ -x "$top/device/google/bluejay/ksu-kernel/fetch-kernel.sh" ] || { echo "[ksu-kernel] fetch script not found under $top" >&2; return 1; }
    ( cd "$top" && device/google/bluejay/ksu-kernel/fetch-kernel.sh device/google/bluejay-kernels/6.1 )
}

# refresh now (envsetup time); never abort the sourcing shell
ksu_kernel_update || echo "[ksu-kernel] WARNING: update failed, see above" >&2

# refresh again on every lunch (wrapped once, even if this file is sourced repeatedly)
if [ -z "${_KSU_LUNCH_WRAPPED:-}" ] && [ "$(type -t lunch 2>/dev/null)" = function ]; then
    eval "_ksu_orig_lunch() $(declare -f lunch | tail -n +2)"
    lunch() { ksu_kernel_update || true; _ksu_orig_lunch "$@"; }
    _KSU_LUNCH_WRAPPED=1
fi
