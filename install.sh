#!/bin/bash
set -e

# PARTITION DEVICES — edit as needed
EFI=/dev/sda1
SWAP=/dev/sda2
ROOT=/dev/sda3

# Format
mkfs.ext4 $ROOT
mkfs.fat -F 32 $EFI
mkswap $SWAP

# Mount
mount $ROOT /mnt
mkdir -p /mnt/boot
mount $EFI /mnt/boot
swapon $SWAP

# Base install
pacstrap /mnt base linux linux-firmware sof-firmware base-devel nano networkmanager systemd-bootctl

# Fstab
genfstab -U /mnt > /mnt/etc/fstab

# Copy second-stage script
cat > /mnt/root/second_stage.sh <<'EOF'
#!/bin/bash
set -e

ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime
hwclock --systohc

sed -i '/en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

echo "Mystic" > /etc/hostname

echo "Set root password:"
passwd

useradd -m -G wheel -s /bin/bash mystic
echo "Set password for mystic:"
passwd mystic

EDITOR=nano visudo  # you'll still need to uncomment wheel access

systemctl enable NetworkManager

bootctl install

PARTUUID=$(blkid -s PARTUUID -o value $(findmnt / -o SOURCE -n))
mkdir -p /boot/loader/entries

cat > /boot/loader/entries/arch.conf <<EOL
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$PARTUUID rw
EOL

cat > /boot/loader/loader.conf <<EOL
default arch
timeout 3
console-mode max
editor no
EOL
EOF

chmod +x /mnt/root/second_stage.sh

# Chroot and run second stage
arch-chroot /mnt /root/second_stage.sh

# Clean up
rm /mnt/root/second_stage.sh

# Unmount
umount -a
echo "Installation done. Reboot now."
