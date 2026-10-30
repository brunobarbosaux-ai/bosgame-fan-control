#!/bin/sh
# Make the amdgpu DPM performance-level sysfs nodes writable, so the GUI can
# switch the GPU performance level without asking for sudo every time.
#
# Why this exists as a separate unit instead of living in fan-control.sh:
#   * sysfs attribute modes are recreated by the kernel on every boot, so the
#     chmod has to be re-applied each boot;
#   * on Strix Halo amdgpu finishes initialising *after* multi-user.target, so a
#     chmod that runs at service start can hit a path that does not exist yet
#     (chmod then fails silently, which is the original bug);
#   * it must not depend on the ec_su_axb35 driver being loaded, because the GPU
#     permission is unrelated to the EC and the module has to be rebuilt after
#     every kernel upgrade.
#
# Override the wait with:  TIMEOUT=120 amdgpu-perms.sh
set -u

TIMEOUT="${TIMEOUT:-60}"

i=0
while ! ls /sys/class/drm/card*/device/power_dpm_force_performance_level \
        >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge "$TIMEOUT" ]; then
        echo "timed out after ${TIMEOUT}s waiting for amdgpu DPM nodes" >&2
        exit 1
    fi
    sleep 1
done

found=0
for f in /sys/class/drm/card*/device/power_dpm_force_performance_level \
         /sys/class/drm/card*/device/power_dpm_state ; do
    [ -e "$f" ] || continue
    # 0666 matches what the GUI documents ("sudo chmod 666 <node>").
    # On multi-user machines prefer: chown root:video "$f"; chmod 0664 "$f"
    chmod 0666 "$f" || exit 1
    found=$((found + 1))
done

[ "$found" -gt 0 ] || { echo "no amdgpu DPM nodes found" >&2; exit 1; }
exit 0
