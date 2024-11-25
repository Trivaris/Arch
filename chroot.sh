#!/bin/bash

# Set the root password

echo -n "Enter the LUKS partition (e.g., sda3): "
read partition3

if [[ "$partition3" =~ ^/dev/nvme ]]; then
    partition_prefix="${partition3}p"
else
    partition_prefix="${partition3}"
fi

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

cat /etc/mkinitcpio.conf

echo "Read the HOOKS line and press Enter to continue..."
read
sleep 10

echo "Updated HOOKS line:"
grep "^HOOKS=" /etc/mkinitcpio.conf

##########################################################################

# Regenerate initramfs for both linux and linux-lts kernels
echo "Regenerating initramfs for linux and linux-lts kernels..."

mkinitcpio -p linux
mkinitcpio -p linux-lts

##########################################################################

# Modify /etc/locale.gen to uncomment the desired locales (en_US.UTF-8 and de_DE.UTF-8)
echo "Modifying /etc/locale.gen to enable 'en_US.UTF-8' and 'de_DE.UTF-8' locales..."

# Uncomment en_US.UTF-8 and de_DE.UTF-8 lines in /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#de_DE.UTF-8/de_DE.UTF-8/' /etc/locale.gen

# Verify the modification
echo "Updated /etc/locale.gen:"
grep -E "en_US.UTF-8|de_DE.UTF-8" /etc/locale.gen

##########################################################################

# Generate the locales
echo "Running locale-gen..."
locale-gen

##########################################################################

# Modify /etc/default/grub to include cryptdevice option
echo "Modifying /etc/default/grub to include 'cryptdevice=/dev/$partition3:volgroup0'..."

# Use sed to add cryptdevice between loglevel=3 and quiet
sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)/\1 cryptdevice=\/dev\/'$partition3':volgroup0 quiet/' /etc/default/grub

# Verify the modification
echo "Updated GRUB_CMDLINE_LINUX_DEFAULT:"
grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub

##########################################################################

# Create the EFI directory and mount the EFI partition
echo "Creating /boot/EFI and mounting the EFI partition..."

mkdir -p /boot/EFI
mount "${partition_prefix}1" /boot/EFI

# Install GRUB for UEFI systems
echo "Installing GRUB for UEFI..."
if ! grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck; then
    echo "GRUB installation failed. Exiting."
    exit 1
fi


##########################################################################

# Copy GRUB locale files for English and German
echo "Copying GRUB locale files..."

# For English locale
cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo

# For German locale
cp /usr/share/locale/de\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/de.mo

##########################################################################

# Regenerate GRUB configuration file
echo "Regenerating GRUB configuration file..."
grub-mkconfig -o /boot/grub/grub.cfg

##########################################################################

# Enable necessary system services
echo "Enabling GDM (GNOME Display Manager) and NetworkManager..."
systemctl enable gdm
systemctl enable NetworkManager

##########################################################################

# Exit the chroot environment
echo "Exiting chroot environment..."
exit 0

##########################################################################

# Verify the modification