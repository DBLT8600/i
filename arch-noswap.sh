#!/bin/bash

set -eo pipefail

if (( DEBUG )); then
    set -x
fi

work_dir=$(mktemp -d "$0-XXXXXXXX")

loader_conf="$work_dir/loader.conf"
cat <<EOF > "$loader_conf"
default arch.conf
timeout 1
EOF

arch_conf="$work_dir/arch.conf"
cat <<EOF > "$arch_conf"
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root="LABEL=arch_os" rw
EOF

en_network="$work_dir/en.network"
cat <<EOF > "$en_network"
[Match]
Name=en*

[Network]
DHCP=yes
EOF

user="arch"
password="$user"
crypted_password=$(echo "$password" | openssl passwd -1 -stdin)

sudoers="$work_dir/sudoers"
cat <<EOF > "$sudoers"
$user ALL=(ALL:ALL) NOPASSWD: ALL
EOF

root_dir="$work_dir/root"
boot_dir="$root_dir/boot"

boot_dev="${1}1"
root_dev="${1}2"

trap 'trap - ERR EXIT; set +eo pipefail; umount -R "$root_dir"; rm -rf "$work_dir"' ERR EXIT INT

boot_size="1024"
boot_start="1"
boot_end=$(( boot_start + boot_size ))

root_start="$boot_end"

parted_args=(
    mklabel gpt
    mkpart esp fat32 "$boot_start"MiB "$boot_end"MiB
    set 1 esp on
    mkpart root ext4 "$root_start"MiB 100%
)

wipefs -af "$1" \
    && parted -s "$1" -- "${parted_args[@]}" \
    && mkfs.ext4 -F "$root_dev" \
    && e2label "$root_dev" arch_os \
    && mkdir "$root_dir" \
    && mount "$root_dev" "$root_dir" \
    && mkfs.fat -F32 "$boot_dev" \
    && mkdir "$boot_dir" \
    && mount "$boot_dev" "$boot_dir" \
    && pacstrap "$root_dir" base linux linux-firmware openssh sudo vi vim \
    && genfstab -U "$root_dir" >> "$root_dir"/etc/fstab \
    && arch-chroot "$root_dir" mkinitcpio -P \
    && arch-chroot "$root_dir" bootctl install \
    && install -m0644 "$loader_conf" "$root_dir"/boot/loader/loader.conf \
    && install -m0644 "$arch_conf" "$root_dir"/boot/loader/entries/arch.conf \
    && install -m0644 "$en_network" "$root_dir"/etc/systemd/network/en.network \
    && arch-chroot "$root_dir" systemctl enable systemd-{networkd,resolved}.service sshd.service \
    && ln -sf /run/systemd/resolve/stub-resolv.conf "$root_dir"/etc/resolv.conf \
    && arch-chroot "$root_dir" timedatectl set-timezone Asia/Tokyo \
    && arch-chroot "$root_dir" timedatectl set-ntp yes \
    && arch-chroot "$root_dir" sed 's/#\(ja_JP.UTF-8 .*\)$/\1/' -i /etc/locale.gen \
    && arch-chroot "$root_dir" locale-gen \
    && arch-chroot "$root_dir" localectl set-locale LANG=ja_JP.UTF-8 \
    && arch-chroot "$root_dir" passwd -l root \
    && arch-chroot "$root_dir" useradd -m "$user" -p "$crypted_password" \
    && install -m0600 "$sudoers" "$root_dir"/etc/sudoers.d/"$user" \
    && echo finish

	
