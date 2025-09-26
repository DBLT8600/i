#!/bin/bash

set -eo pipefail

if (( UID )); then
    echo "sudo $0" >&2; exit 1
fi

is_aarch64=0
if [[ "$1" == '-64' || "$1" == '--64' ]]; then
    is_aarch64=1; shift
fi

dev="$1"
boot="${dev}p1"
root="${dev}p2"

is_usbboot=0
if [[ "$dev" =~ /dev/sd* ]]; then
    boot="${dev}1" root="${dev}2" is_usbboot=1; shift
fi

echo "wipefs"

wipefs -a "$dev"

echo "parted"

parted -s "$dev" -- mklabel msdos mkpart primary fat32 1MiB 513MiB mkpart primary ext4 513MiB 100%

tmp=$(mktemp -d "$PWD/tmp-XXXXXXXX")
bootdir="$tmp/boot"
rootdir="$tmp/root"
install -Ddm755 "$bootdir" "$rootdir"

echo "mkfs.vfat $boot"

mkfs.vfat "$boot"
mount "$boot" "$bootdir"

echo "mkfs.ext4 $root"

mkfs.ext4 -F "$root"
mount "$root" "$rootdir"

trap 'trap - ERR EXIT; umount "$bootdir" "$rootdir"; rm -rf "$tmp"' ERR EXIT INT

url=http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-armv7-latest.tar.gz
if (( $is_aarch64 )); then
    url=http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz
fi

echo "curl $url"

curl -fsSL "$url" | bsdtar -xf - -C "$rootdir"
sync

mv "$rootdir/boot"/* "$bootdir"

if (( $is_usbboot )); then
    sed "s,/dev/mmcblk0p,/dev/sda," -i "$rootdir/etc/fstab"

    if [[ -f "$bootdir/cmdline.txt" ]]; then
        sed "s,/dev/mmcblk0p,/dev/sda," -i "$bootdir/cmdline.txt"
    fi
fi
