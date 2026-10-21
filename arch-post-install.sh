#!/bin/bash

# ======================================================
# === Hyprland Post-Installation and Dotfiles Script ===
# ======================================================

# This script automates the setup of Hyprland, Waybar, and other
# configuration files after a fresh Arch Linux installation.
# It should be run as the new user, not as root.

# Exit immediately if a command exits with a non-zero status.
set -e

# =========================================================
# === 1. User-Configurable Variables (EDIT THIS SECTION) ===
# =========================================================

# Your username, as defined in the installation script.
USERNAME=""

# The directory where your dotfiles are located.
# This could be a git repository you cloned.
DOTFILES_DIR="/home/$USERNAME/Downloads/arch-setup/dotfiles"

# Greetd configuration
# Set USE_GREETD="true" to use greetd as the display manager.
# sddm configuration has been removed.
USE_GREETD="true"

# ==========================================
# === 2. Script Functions (DO NOT EDIT) ===
# ==========================================

# Function to check if the dotfiles directory exists
check_dotfiles_dir() {
    echo "==> Checking for dotfiles directory..."
    if [ ! -d "$DOTFILES_DIR" ]; then
        echo "Error: Dotfiles directory '$DOTFILES_DIR' not found."
        echo "Please edit the script and set the correct path."
        exit 1
    fi
}

# Function to copy configuration files and make scripts executable
copy_dotfiles() {
    echo "==> Copying dotfiles..."
    
    # Hyprland, Waybar, and Mako configurations
    # This assumes your configs are in a subdirectory like dotfiles/config/hypr, etc.
    cp -r "$DOTFILES_DIR/config/hypr" "/home/$USERNAME/.config/"
    cp -r "$DOTFILES_DIR/config/waybar" "/home/$USERNAME/.config/"
    cp -r "$DOTFILES_DIR/config/mako" "/home/$USERNAME/.config/"
    
    # Add other configurations here, for example:
    cp -r "$DOTFILES_DIR/config/kitty" "/home/$USERNAME/.config/" || echo "kitty cfg not present"

    # Make scripts executable
    echo "==> Making scripts in hypr and waybar executable..."
    find "/home/$USERNAME/.config/hypr/scripts" -type f -exec chmod +x {} \;
    find "/home/$USERNAME/.config/waybar/scripts" -type f -exec chmod +x {} \;

    echo "==> Dotfiles copied and scripts are now executable."
}

# Function to configure the display manager (greetd)
configure_display_manager() {
    echo "==> Configuring display manager..."
    if [ "$USE_GREETD" = "true" ]; then
        # Install greetd and tui-greet
        # The user should have these packages pre-installed or add them
        # to the main installation script's PACKAGES list.
        sudo pacman -S --noconfirm greetd tui-greet
        
        # Configure greetd to use tui-greet
        sudo bash -c 'echo "[terminal]\nuser = greeter\n\n[default]\nuser = greeter\ninitial_session = tui-greet -c hyprland" > /etc/greetd/config.toml'
        sudo systemctl enable greetd.service
    else
        echo "Warning: No display manager configured. Please configure one manually."
    fi
    echo "==> Display manager configured."
}

# Function to apply faillock changes
configure_faillock() {
    echo "==> Applying faillock configuration..."
    # This example replaces the default file with a custom one from your dotfiles.
    # Be sure to have the file at: $DOTFILES_DIR/etc/faillock.conf
    # Example faillock.conf content:
    # [local]
    # deny = 3
    # unlock_time = 600
    # even_deny_root
    if [ -f "$DOTFILES_DIR/etc/security/faillock.conf" ]; then
        echo "==> Backing up original /etc/security/faillock.conf..."
        sudo cp "/etc/security/faillock.conf" "/etc/security/faillock.conf.bak.$(date +%Y%m%d%H%M%S)"
        sudo cp "$DOTFILES_DIR/etc/security/faillock.conf" "/etc/security/"
        echo "==> /etc/security/faillock.conf updated with your custom configuration."
    else
        echo "Warning: No faillock.conf found in dotfiles. Skipping."
    fi
}

# Main function to run all post-installation steps
main() {
    check_dotfiles_dir
    copy_dotfiles
    configure_display_manager
    configure_faillock
    echo "==> Post-installation setup complete. Please reboot for changes to take effect."
}

# Run the main function
main
