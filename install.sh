#!/bin/bash

# ========= CONFIG =========
EFI=/dev/sda1
SWAP=/dev/sda2
ROOT=/dev/sda3
LOGFILE="/tmp/arch_install.log"
set -o pipefail

log() {
    echo "[+] $1" | tee -a "$LOGFILE"
}
fail() {
    echo "[!] ERROR: $1" | tee -a "$LOGFILE"
    exit 1
}
trap 'fail "Script interrupted or failed."' ERR

# ========= PRE-CHECKS =========
log "Checking internet..."
ping -q -c 1 archlinux.org >/dev/null || fail "No internet connection."

log "Verifying partitions exist..."
for dev in "$EFI" "$SWAP" "$ROOT"; do
    [ -b "$dev" ] || fail "Device $dev not found."
done

# ========= FORMAT =========
log "Formatting partitions..."
mkfs.ext4 -F "$ROOT" | tee -a "$LOGFILE"
mkfs.fat -F 32 "$EFI" | tee -a "$LOGFILE"
mkswap "$SWAP" | tee -a "$LOGFILE"

# ========= MOUNT =========
log "Mounting partitions..."
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot
swapon "$SWAP"

# ========= INSTALL BASE =========
log "Installing base system..."
pacstrap /mnt base linux linux-firmware sof-firmware base-devel nano networkmanager | tee -a "$LOGFILE"

log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# ========= SECOND STAGE =========
log "Writing second stage setup..."
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

PASSWORD='My5T!c@#'
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash mystic
echo "mystic:$PASSWORD" | chpasswd


sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers

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

# === POST-INSTALL: GNOME Desktop ===
echo "[+] Installing GNOME and enabling GDM..."
pacman -Sy --noconfirm gnome gnome-tweaks
systemctl enable gdm

EOF

chmod +x /mnt/root/second_stage.sh

# ========= CHROOT =========
log "Running second stage inside chroot..."
arch-chroot /mnt /root/second_stage.sh

# ========= CLEANUP =========
log "Cleaning up..."
rm /mnt/root/second_stage.sh
umount -a
log "Installation complete. Reboot to enter Arch."

