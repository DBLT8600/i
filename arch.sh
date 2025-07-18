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

wired_network=$(mktemp)

cat <<EOF > "$wired_network"
[Match]
Name=en*

[Network]
DHCP=yes
EOF

trap 'umount -R /mnt' ERR

parted -s "$1" -- mklabel gpt mkpart ESP fat32 1MiB 261MiB set 1 esp on mkpart root ext4 261MiB 100% \
    && mkfs.fat -F32 "${1}1" \
    && mkfs.ext4 "${1}2" \
    && e2label "${1}2" arch_os \
    && mount "${1}2" /mnt \
    && mkdir /mnt/boot \
    && mount "${1}1" /mnt/boot \
    && sed 's/^#\(Parallel.*\)$/\1/' -i /etc/pacman.conf \
    && pacstrap /mnt base linux linux-firmware rng-tools openssh sudo avahi nss-mdns \
    && genfstab -U /mnt >> /mnt/etc/fstab \
    && arch-chroot /mnt mkinitcpio -P \
    && arch-chroot /mnt bootctl install \
    && install -m0644 "$loader_conf" /mnt/boot/loader/loader.conf \
    && install -m0644 "$arch_conf" /mnt/boot/loader/entries/arch.conf \
    && install -m0644 "$wired_network" /mnt/etc/systemd/network/en.network \
    && arch-chroot /mnt passwd -l root \
    && arch-chroot /mnt useradd -m arch \
    && arch-chroot /mnt usermod -a -G wheel arch \
    && arch-chroot /mnt passwd arch < <(printf '%s\n' arch arch) \
    && sed 's/^# \(%wheel ALL=(ALL:ALL) ALL\)$/\1/' -i /mnt/etc/sudoers \
    && sed 's/^\(hosts: [^ ]*\) \(.*\)$/\1 mdns_minimal [NOTFOUND=return] \2/' -i /mnt/etc/nsswitch.conf \
    && arch-chroot /mnt systemctl enable systemd-{networkd,resolved}.service rngd.service sshd.service avahi-daemon.service \
    && ln -fs /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf \
    && umount -R /mnt \
    && reboot
