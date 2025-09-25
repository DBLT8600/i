#!/bin/bash

set -eo pipefail

if (( DEBUG )); then
    set -x
fi

config=()

loader_conf=$(mktemp)
config+=("$loader_conf")

cat <<EOF > "$loader_conf"
default arch.conf
timeout 1
EOF

arch_conf=$(mktemp)
config+=("$arch_conf")

cat <<EOF > "$arch_conf"
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root="LABEL=arch_os" rw
EOF

en_network=$(mktemp)
config+=("$en_network")

cat <<EOF > "$en_network"
[Match]
Name=en*

[Network]
DHCP=yes
EOF

sudoers=$(mktemp)
config+=("$sudoers")

cat <<EOF > "$sudoers"
arch ALL=(ALL:ALL) NOPASSWD: ALL
EOF

trap 'trap - ERR EXIT; set +eo pipefail; rm -f "${config[@]}"; umount -R /mnt' ERR EXIT INT

boot_dev="${1}1"
root_dev="${1}2"

boot_size=1024
boot_start=1
boot_end=$(( boot_start + boot_size ))

root_start=$boot_end
root_end=100%

parted_args=(
    mklabel gpt
    mkpart esp fat32 ${boot_start}MiB ${boot_end}MiB
    set 1 esp on
    mkpart root ext4 ${root_start}MiB $root_end
)

pw=$(echo arch | openssl passwd -1 -stdin)

parted -s "$1" -- "${parted_args[@]}" \
    && mkfs.ext4 -F "$root_dev" \
    && e2label "$root_dev" arch_os \
    && mount "$root_dev" /mnt \
    && mkfs.fat -F32 "$boot_dev" \
    && mkdir /mnt/boot \
    && mount "$boot_dev" /mnt/boot \
    && sed 's/^#\(Parallel.*\)$/\1/' -i /etc/pacman.conf \
    && pacstrap /mnt base linux linux-firmware openssh sudo vi vim \
    && genfstab -U /mnt >> /mnt/etc/fstab \
    && arch-chroot /mnt mkinitcpio -P \
    && arch-chroot /mnt bootctl install \
    && install -m0644 "$loader_conf" /mnt/boot/loader/loader.conf \
    && install -m0644 "$arch_conf" /mnt/boot/loader/entries/arch.conf \
    && arch-chroot /mnt systemctl enable systemd-{networkd,resolved}.service sshd.service \
    && install -m0644 "$en_network" /mnt/etc/systemd/network/en.network \
    && ln -fs /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf \
    && arch-chroot /mnt timedatectl set-timezone Asia/Tokyo \
    && arch-chroot /mnt timedatectl set-ntp yes \
    && arch-chroot /mnt sed 's/#\(ja_JP.UTF-8 .*\)$/\1/' -i /etc/locale.gen \
    && arch-chroot /mnt locale-gen \
    && arch-chroot /mnt localectl set-locale LANG=ja_JP.UTF-8 \
    && arch-chroot /mnt passwd -l root \
    && arch-chroot /mnt useradd -m arch -p $pw \
    && install -m0600 "$sudoers" /mnt/etc/sudoers.d/arch \
    && echo finish
