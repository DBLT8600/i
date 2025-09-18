#!/bin/bash

set -eo pipefail

if (( DEBUG )); then
    set -x
fi

loader_conf=$(mktemp)

cat <<EOF > "$loader_conf"
default arch.conf
timeout 1
EOF

arch_conf=$(mktemp)

cat <<EOF > "$arch_conf"
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root="LABEL=arch_os" rw
EOF

network_conf=$(mktemp)

cat <<EOF > "$network_conf"
[Match]
Name=en*

[Network]
DHCP=yes
EOF

trap 'trap - ERR; rm -f "$loader_conf" "$arch_conf" "$network_conf"; umount -R /mnt' ERR INT

# $0 /dev/sda boot_size swap_size

target_dev=$1
shift

boot_size=1024

if (( $# )); then
    boot_size="$1"
    shift
fi

swap_size=0

if (( $# )); then
    swap_size="$1"
    shift
fi

boot_dev=${target_dev}1
root_dev=${target_dev}2

boot_start=1MiB
boot_end=$(( ${boot_start%MiB} + boot_size ))MiB

root_start=$boot_end
root_end=100%

parted_args=(
    mklabel gpt
    mkpart ESP  fat32 ${boot_start} ${boot_end} set 1 esp on
    mkpart root ext4  ${root_start} ${root_end}
)

if (( swap_size )); then
    swap_dev=${target_dev}2
    root_dev=${target_dev}3

    swap_start=$boot_end
    swap_end=$(( ${swap_start%MiB} + swap_size ))MiB

    root_start=$swap_end

    parted_args=(
        mklabel gpt
        mkpart ESP  fat32      ${boot_start} ${boot_end} set 1 esp on
        mkpart swap linux-swap ${swap_start} ${swap_end}
        mkpart root ext4       ${root_start} ${root_end}
    )
fi

parted -s "$target_dev" -- "${parted_args[@]}"

mkfs.fat -F32 "$boot_dev"
mkfs.ext4 "$root_dev"

if (( swap_size )); then
    mkswap "$swap_dev"
    swapon "$swap_dev"
fi

e2label "$root_dev" arch_os

mount "$root_dev" /mnt

mkdir /mnt/boot
mount "$boot_dev" /mnt/boot

sed '/# Misc options/a ILoveCandy' -i /etc/pacman.conf
sed 's/^#\(Color\)$/\1/; s/^#\(Parallel.*\)$/\1/' -i /etc/pacman.conf

pacstrap /mnt base linux linux-firmware rng-tools openssh sudo vi

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt mkinitcpio -P
arch-chroot /mnt bootctl install

install -m0644 "$loader_conf" /mnt/boot/loader/loader.conf
install -m0644 "$arch_conf" /mnt/boot/loader/entries/arch.conf
install -m0644 "$network_conf" /mnt/etc/systemd/network/en.network

arch-chroot /mnt passwd -l root

arch-chroot /mnt useradd -m arch
arch-chroot /mnt usermod -a -G wheel arch
arch-chroot /mnt passwd arch < <(printf '%s\n' arch arch)
sed 's/^# \(%wheel ALL=(ALL:ALL) ALL\)$/\1/' -i /mnt/etc/sudoers

arch-chroot /mnt systemctl enable systemd-{networkd,resolved}.service rngd.service sshd.service
ln -fs /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

umount -R /mnt
poweroff
