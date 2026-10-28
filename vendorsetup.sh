# Sourced by build/envsetup.sh (device/*/*/vendorsetup.sh).
#
# Lineage's `lunch` runs build_kernel: it syncs + builds the kernel in out-kernel/google/gs-6.1, WIPES
# device/google/bluejay-kernels/6.1 and copies the unpatched build there. After lunch succeeds we run
# ksu-kernel/patch-kernel.sh, which builds kernelsu.ko against that same kernel and patches boot.img.
#
#   ksu_kernel_patch     run the patch step by hand (after lunch / when the build warns it is unpatched)
#   KSU_SKIP=1           skip patching          KSU_FORCE=1   patch again

ksu_kernel_patch() {
    local top
    top=$(gettop 2>/dev/null) || top=$PWD
    [ -x "$top/device/google/bluejay/ksu-kernel/patch-kernel.sh" ] || { echo "[ksu-kernel] patch script not found under $top" >&2; return 1; }
    ( cd "$top" && ANDROID_BUILD_TOP="$top" device/google/bluejay/ksu-kernel/patch-kernel.sh )
}

# Wrap lunch once. Decide from lunch's own definition, not from a variable: re-sourcing envsetup.sh in the
# same shell redefines lunch (dropping an earlier wrapper) while shell variables survive.
if [ "$(type -t lunch 2>/dev/null)" = function ] && ! declare -f lunch | grep -q '_ksu_orig_lunch'; then
    eval "_ksu_orig_lunch() $(declare -f lunch | tail -n +2)"
    lunch() {
        _ksu_orig_lunch "$@"
        local rc=$?
        if [ $rc -eq 0 ]; then
            ksu_kernel_patch || echo "[ksu-kernel] WARNING: patching failed, the ROM will NOT contain KernelSU-Next (run ksu_kernel_patch)" >&2
        fi
        return $rc
    }
fi
