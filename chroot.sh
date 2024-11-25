#!/bin/bash

# Set the root password

echo -n "Enter the LUKS partition (e.g., sda3): "
read partition3

echo -n "Enter the root password: "
passwd

##########################################################################

# Ask for a new username and create the user
echo -n "Enter a username to create: "
read username
useradd -m -g users -G wheel "$username"

# Set password for the new user
echo -n "Enter the password for the user $username: "
passwd "$username"

##########################################################################

# Install essential packages and desktop environment
pacman -S base-devel dosfstools grub efibootmgr gnome gnome-tweaks lvm2 mtools neovim networkmanager openssh sudo --noconfirm

sleep 1

# Enable SSH service
systemctl enable sshd

##########################################################################

# Install the kernel and related packages
pacman -S linux linux-headers linux-lts linux-lts-headers --noconfirm

# Install firmware packages
pacman -S linux-firmware --noconfirm

##########################################################################

# Ask the user about their GPU (Intel or Nvidia)
echo -n "Do you have an Intel or Nvidia GPU? (intel/nvidia): "
read gpu_choice

# Install GPU drivers based on user input
if [[ "$gpu_choice" == "intel" ]]; then
    # Install Intel GPU drivers
    pacman -S mesa --noconfirm
    pacman -S intel-media-driver --noconfirm
    echo "Intel GPU drivers installed."

elif [[ "$gpu_choice" == "nvidia" ]]; then
    # Install Nvidia GPU drivers
    pacman -S nvidia nvidia-utils nvidia-lts --noconfirm
    echo "Nvidia GPU drivers installed."
else
    echo "Invalid choice for GPU. Please enter 'intel' or 'nvidia'."
    exit 1
fi

##########################################################################

# Modify /etc/mkinitcpio.conf to add "encrypt" and "lvm2" in the HOOKS line
echo "Modifying /etc/mkinitcpio.conf to include 'encrypt' and 'lvm2' in HOOKS..."

# Backup the original mkinitcpio.conf before modifying
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak

# Use sed to insert "encrypt" and "lvm2" between "block" and "filesystems" in the HOOKS line
sed -i 's/\(HOOKS=\([^\)]*\)block\)/\1 encrypt lvm2/' /etc/mkinitcpio.conf

# Verify the modification