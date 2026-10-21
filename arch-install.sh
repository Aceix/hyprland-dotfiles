#!/bin/bash

# ===============================================
# === Arch Linux Automated Installation Script ===
# ===============================================

# WARNING: This script is highly destructive. It will partition and format
# the selected disk, erasing all existing data.
# Review the configuration variables below carefully before running.

# Exit immediately if a command exits with a non-zero status.
set -e

# =========================================================
# === 1. User-Configurable Variables (EDIT THIS SECTION) ===
# =========================================================

# The target disk to install Arch Linux on.
# e.g., /dev/sda, /dev/nvme0n1
# !!! CAUTION: All data on this disk will be ERASED. !!!
DISK=""

# System and User Information
HOSTNAME="my-arch-hyprland"
USERNAME="archuser"
PASSWORD="mysecurepassword"    # Change this to a strong password
ROOT_PASSWORD="myrootpassword" # Change this as well

# Geographic and Locale Settings
TIMEZONE="Africa/Accra"
LOCALE="en_GB.UTF-8"
KEYMAP="us"

# Disk Partitioning Sizes
# Note: Root partition size is specified in GiB, Home partition will use the rest.
ROOT_PARTITION_SIZE="50GiB"

# Additional packages to install (customize this list)
# Example includes Hyprland, a terminal, and a basic set of utilities.
PACKAGES=(
  base
  base-devel
  linux
  linux-firmware
  intel-ucode
  vim
  nano
  git
  networkmanager
  reflector
  grub
  efibootmgr

  # Desktop Environment & Utilities
  hyprland
  hyprpaper
  kitty
  waybar
  pipewire
  pipewire-pulse
  wireplumber
  xdg-desktop-portal-hyprland

  # Essential tools
  brave
  neovim
  cmake
  ninja
  gcc
  make
)

# ==========================================
# === 2. Installation Functions (DO NOT EDIT) ===
# ==========================================

# Function to check for internet connection
check_internet() {
  echo "==> Checking for internet connection..."
  ping -c 3 archlinux.org || {
    echo "Error: Internet connection not found. Please connect to the internet first."
    exit 1
  }
}

# Function to update mirrors
update_mirrors() {
  echo "==> Updating Pacman mirrors..."
  reflector --country Germany --latest 5 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
}

# Function for disk partitioning
setup_disk() {
  echo "==> Partitioning and formatting disk $DISK..."
  echo "!!! All data on $DISK will be ERASED. Are you sure? (yes/no)"
  read -p "Enter 'yes' to proceed: " CONFIRM
  if [[ ! "$CONFIRM" == "yes" ]]; then
    echo "Aborting installation."
    exit 1
  fi

  # Clear old partition tables
  sgdisk --zap-all "$DISK"

  # Create new partitions:
  # 1. EFI System Partition (512MB)
  # 2. Linux Root Partition (user-defined size)
  # 3. Linux Home Partition (all remaining space)
  sgdisk -n 1:2048:1050623 -t 1:ef00 -c 1:"EFI System" "$DISK"
  sgdisk -n 2:1050624:+$ROOT_PARTITION_SIZE -t 2:8300 -c 2:"Linux Root" "$DISK"
  sgdisk -n 3:0:0 -t 3:8300 -c 3:"Linux Home" "$DISK"

  # Format partitions
  mkfs.fat -F32 "${DISK}p1"
  mkfs.ext4 "${DISK}p2"
  mkfs.ext4 "${DISK}p3"

  # Mount partitions
  mount "${DISK}p2" /mnt
  mkdir -p /mnt/boot/efi
  mount "${DISK}p1" /mnt/boot/efi
  mkdir -p /mnt/home
  mount "${DISK}p3" /mnt/home

  echo "==> Disk partitioning and formatting complete."
}

# Function to install the base system
install_base_system() {
  echo "==> Installing the base system and kernel..."
  pacstrap /mnt "${PACKAGES[@]}"
  echo "==> Base system installation complete."
}

# Function for chroot configuration
chroot_setup() {
  arch-chroot /mnt /bin/bash -c "
        echo '==> Inside chroot: Configuring the system...'

        # Generate fstab
        genfstab -U /mnt >> /etc/fstab

        # Timezone and Locale
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        hwclock --systohc
        echo 'LANG=$LOCALE' > /etc/locale.conf
        echo '$LOCALE UTF-8' >> /etc/locale.gen
        locale-gen

        # Hostname
        echo '$HOSTNAME' > /etc/hostname

        # Set passwords
        echo '==> Setting root password...'
        echo -e '$ROOT_PASSWORD\n$ROOT_PASSWORD' | passwd

        # Add user
        echo '==> Creating new user: $USERNAME'
        useradd -m -G wheel,audio,video,storage,input -s /bin/bash '$USERNAME'
        echo -e '$PASSWORD\n$PASSWORD' | passwd '$USERNAME'

        # Enable sudo for the wheel group
        echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-custom-sudo

        # Bootloader installation (GRUB for UEFI)
        echo '==> Installing and configuring GRUB bootloader...'
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
        grub-mkconfig -o /boot/grub/grub.cfg

        # Enable services
        echo '==> Enabling essential services...'
        systemctl enable NetworkManager

        echo '==> Chroot configuration complete.'
    "
}

# Main function to orchestrate the installation
main() {
  check_internet
  update_mirrors
  setup_disk
  install_base_system
  chroot_setup

  echo "==> Installation complete! Rebooting in 5 seconds..."
  sleep 5
  reboot
}

# Run the main function
main
