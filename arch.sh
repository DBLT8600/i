#!/bin/bash

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

parted -s "$1" -- mklabel gpt mkpart ESP fat32 1MiB 401MiB set 1 esp on mkpart root ext4 401MiB 100% \
    && mkfs.fat -F32 "${1}1" \
    && mkfs.ext4 "${1}2" \
    && e2label "${1}2" arch_os \
    && mount "${1}2" /mnt \
    && mkdir /mnt/boot \
    && mount "${1}1" /mnt/boot \
    && sed 's/^#\(Parallel.*\)$/\1/' -i /etc/pacman.conf \
    && pacstrap /mnt base linux linux-firmware rng-tools openssh sudo vi \
    && genfstab -U /mnt >> /mnt/etc/fstab \
    && arch-chroot /mnt mkinitcpio -P \
    && arch-chroot /mnt bootctl install \
    && install -m0644 "$loader_conf" /mnt/boot/loader/loader.conf \
    && install -m0644 "$arch_conf" /mnt/boot/loader/entries/arch.conf \
    && install -m0644 "$network_conf" /mnt/etc/systemd/network/en.network \
    && arch-chroot /mnt passwd -l root \
    && arch-chroot /mnt useradd -m arch \
    && arch-chroot /mnt usermod -a -G wheel arch \
    && arch-chroot /mnt passwd arch < <(printf '%s\n' arch arch) \
    && sed 's/^# \(%wheel ALL=(ALL:ALL) ALL\)$/\1/' -i /mnt/etc/sudoers \
    && arch-chroot /mnt systemctl enable systemd-{networkd,resolved}.service rngd.service sshd.service \
    && ln -fs /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf \
    && umount -R /mnt \
    && reboot
