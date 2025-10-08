#!/bin/bash
# =====================================================
# archchroot_ : Smart Arch Linux Chroot Helper (Ventoy)
# -----------------------------------------------------
# - Auto-detects Arch root partition
# - Auto-suggests EFI partition
# - Mounts all system dirs
# - Enters chroot
# - Backs up existing GRUB EFI loader
# - Cleans up (unmounts everything) on exit
# =====================================================

set -e

echo "=============================================="
echo "   Smart Arch Linux Chroot Helper (Ventoy)"
echo "=============================================="
echo

lsblk -e7 -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part"
echo

# --- Auto-detect Arch root partitions ---
echo ">>> Scanning for Arch Linux installations..."
ROOTCANDIDATES=()
for part in /dev/*; do
  [[ $part =~ [0-9]$ ]] || continue
  mountdir=$(mktemp -d)
  mount "$part" "$mountdir" 2>/dev/null || continue
  if [ -f "$mountdir/etc/arch-release" ]; then
    ROOTCANDIDATES+=("$part")
  fi
  umount "$mountdir" 2>/dev/null
  rmdir "$mountdir"
done

if [ ${#ROOTCANDIDATES[@]} -gt 0 ]; then
  echo "✅ Found possible Arch root partitions:"
  i=1
  for p in "${ROOTCANDIDATES[@]}"; do
    echo "  [$i] $p"
    ((i++))
  done
  echo
  read -rp "Choose a number or enter manually: " choice
  if [[ $choice =~ ^[0-9]+$ ]]; then
    ROOTPART=${ROOTCANDIDATES[$((choice-1))]}
  else
    ROOTPART="$choice"
  fi
else
  echo "⚠️ No Arch partitions auto-detected."
  read -rp "Enter your ROOT partition (e.g. /dev/nvme0n1p2): " ROOTPART
fi

if [ ! -b "$ROOTPART" ]; then
  echo "❌ Invalid root partition: $ROOTPART"
  exit 1
fi

mkdir -p /mnt
mount "$ROOTPART" /mnt || { echo "❌ Failed to mount root."; exit 1; }

# --- Detect EFI partition ---
echo
echo ">>> Checking for EFI partition..."
EFIPART=$(lsblk -o NAME,FSTYPE,MOUNTPOINT | grep -i vfat | awk '{print "/dev/" $1}' | head -n1)
if [ -n "$EFIPART" ]; then
  echo "Found possible EFI: $EFIPART"
  read -rp "Use this EFI partition? [Y/n]: " ans
  [[ "$ans" =~ ^[Nn]$ ]] && read -rp "Enter EFI partition manually: " EFIPART
else
  read -rp "Enter EFI partition (or leave blank to skip): " EFIPART
fi

if [ -n "$EFIPART" ]; then
  mkdir -p /mnt/boot/efi
  mount "$EFIPART" /mnt/boot/efi && echo "✅ EFI mounted at /mnt/boot/efi"
else
  echo "⚠️ Skipping EFI mount."
fi

# --- Optional GRUB EFI backup ---
if [ -d "/mnt/boot/efi/EFI/GRUB" ]; then
  BACKUP_DIR="/mnt/root/efi_grub_backup_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  echo
  echo ">>> Backing up GRUB EFI files..."
  cp -r /mnt/boot/efi/EFI/GRUB "$BACKUP_DIR"/
  echo "✅ Backup saved to $BACKUP_DIR"
else
  echo "⚠️ No GRUB EFI directory found to back up."
fi

# --- Mount pseudo-filesystems ---
echo
echo ">>> Mounting system pseudo-filesystems..."
mount -t proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/sys
mount --make-rslave /mnt/dev
mount --rbind /run /mnt/run

# --- Mount EFI variables ---
echo ">>> Mounting EFI vars..."
mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars 2>/dev/null || echo "⚠️ EFI vars already mounted or unavailable."

echo
echo "✅ All mounts done."
echo ">>> Entering chroot (type 'exit' when done)..."
echo

arch-chroot /mnt

# --- Cleanup after chroot exit ---
echo
echo ">>> Cleaning up mounts..."
umount -R /mnt/boot/efi 2>/dev/null || true
umount -R /mnt/run 2>/dev/null || true
umount -R /mnt/sys 2>/dev/null || true
umount -R /mnt/dev 2>/dev/null || true
umount -R /mnt/proc 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

echo
echo "✅ Cleanup complete. Backup (if created) is in:"
ls -d /mnt/root/efi_grub_backup_* 2>/dev/null || echo "No backup made this session."
echo "You can now safely reboot."

