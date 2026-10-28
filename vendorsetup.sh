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
        # Patch whatever lunch's build_kernel produced, even if lunch itself returned non-zero: many ROM lunch
        # functions end on a command whose status is not 0 although everything worked. patch-kernel.sh is a
        # no-op when boot.img is already patched, so running it after a failed lunch is harmless.
        echo "[ksu-kernel] lunch finished (exit $rc), checking the KernelSU-Next patch..." >&2
        ksu_kernel_patch || echo "[ksu-kernel] WARNING: patching failed, the ROM will NOT contain KernelSU-Next (run ksu_kernel_patch)" >&2
        return $rc
    }
fi
