#!/bin/bash

set -eo pipefail

if (( DEBUG )); then
    set -x
fi

if (( UID )); then
    echo "sudo $0" >&2; exit 1
fi

tmp=$(mktemp -d "$PWD/tmp-XXXXXXXX")

trap 'trap - ERR EXIT; umount -R "$tmp"; rm -rf "$tmp"' ERR EXIT INT

boot_dev=${1}p1
root_dev=${1}p2

boot_size=1024
boot_start=1
boot_end=$(( boot_start + boot_size ))

root_start=$boot_end

parted_args=(
    mklabel msdos
    mkpart boot fat32 ${boot_start}MiB ${boot_end}MiB
    mkpart root ext4 ${root_start}MiB 100%
)

url=http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-armv7-latest.tar.gz

parted -s "$1" -- "${parted_args[@]}" \
    mkfs.ext4 -F "$root_dev" \
    mount "$root_dev" "$tmp" \
    mkfs.vfat "$boot_dev" \
    mkdir "$tmp/boot" \
    mount "$boot_dev" "$tmp/boot" \
    curl -fsSL "$url" | bsdtar -xf - -C "$tmp" \
    sync \
    echo finish
