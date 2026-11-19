# SPDX-License-Identifier: MIT

# NOTE: These functions are used in the initramfs, so they must be ash/busybox compatible!
#
# Aurora's copy of these functions from https://github.com/asahi-alarm/asahi-scripts
# (tag 20261023), with the device tree property and ESP layout renamed.

# The ESP PARTUUID aura publishes in /chosen. LEGACY-ASAHI(2027-02-28): an
# aura from before the rename publishes it only as asahi,efi-system-partition.
aurora_esp_uuid() {
    for prop in aurora,efi-system-partition asahi,efi-system-partition; do
        if [ -e "/proc/device-tree/chosen/$prop" ]; then
            sed 's/\x00//' "/proc/device-tree/chosen/$prop"
            return 0
        fi
    done
}

# An ESP holds aura's Stage 2 under aurora/. LEGACY-ASAHI(2027-02-28): a
# Stage 1 enrolled before the rename loads it from m1n1/.
aurora_is_esp() {
    [ -e "$1/aurora" ] || [ -e "$1/m1n1" ]
}

# The ESP directory holding the Stage 2 this Mac's Stage 1 chainloads: aurora,
# or m1n1 for a Stage 1 enrolled before the rename that still loads it there
# (enrolling a new Stage 1 is the owner's step). LEGACY-ASAHI(2027-02-28).
aurora_stage2_dir() {
    if [ ! -e "$1/aurora/boot.bin" ] && [ ! -e "$1/aurora/boot-ctxr.bin" ] &&
        { [ -e "$1/m1n1/boot.bin" ] || [ -e "$1/m1n1/boot-ctxr.bin" ]; }; then
        echo m1n1
    else
        echo aurora
    fi
}

info() {
    quiet=0
    if [ -e /lib/dracut-lib.sh ]; then
        if grep -q "rd.debug" /proc/cmdline; then
            quiet=0
        elif grep -q "quiet" /proc/cmdline; then
            quiet=1
        fi
    fi

    [ "$quiet" -eq 0 ] && echo "$@" 1>&2
}

warn() {
    echo "$@" 1>&2
}

mount_sys_esp() {
    set -e
    mountpoint="$1"

    mkdir -p "$mountpoint"
    while grep -q " $mountpoint " /proc/mounts; do
        umount "$mountpoint"
    done

    esp_uuid="$(aurora_esp_uuid 2>/dev/null)"
    if [ -e /boot/efi/.builder ] || [ -e /boot/.builder ] || [ -z "$esp_uuid" ]; then
        if aurora_is_esp /boot/efi; then
            bootmnt="/boot/efi"
        elif aurora_is_esp /boot; then
            bootmnt="/boot"
        else
            warn "ESP not found and cannot determine ESP PARTUUID."
            warn "Make sure that your aura has the right aurora,efi-system-partition configuration,"
            warn "or that your ESP is mounted at /boot/efi or /boot."
            return 1
        fi
        mount --bind "$bootmnt" "$mountpoint"
        warn "System ESP not identified in device tree, using $bootmnt"
    else
        mount "PARTUUID=$esp_uuid" "$mountpoint"
    fi
    dev="$(grep "$mountpoint" /proc/mounts | cut -d" " -f1)"
    info "Mounted System ESP $dev at $mountpoint"
}

mount_boot_esp() {
    set -e
    mountpoint="$1"

    mkdir -p "$mountpoint"
    while grep -q " $mountpoint " /proc/mounts; do
        umount "$mountpoint"
    done

    if [ -e "/boot/efi/efi/boot" ]; then
        mount --bind "/boot/efi" "$mountpoint"
    elif [ -e "/boot/efi/boot" ]; then
        mount --bind "/boot" "$mountpoint"
    else
        esp_uuid="$(aurora_esp_uuid)"

        if [ -z "$esp_uuid" ]; then
            echo "Boot ESP not found and cannot determine ESP PARTUUID."
            echo "Make sure your ESP is mounted at /boot/efi or /boot,"
            echo "or that your aura has the right aurora,efi-system-partition configuration."
            return 1
        fi

        mount "PARTUUID=$esp_uuid" "$mountpoint"
    fi
    info "Mounted Boot ESP at $mountpoint"
}
