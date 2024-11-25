#!/bin/bash
clear

# Set the root password
partition_prefix="${1}"
partition3="${partition_prefix}3"

echo -n -e "\e[31mEnter the root password:\e[0m "
passwd

##########################################################################

# Ask for a new username and create the user
echo -n -e "\e[31mEnter a username to create:\e[0m "
read username
useradd -m -g users -G wheel "$username"

# Set password for the new user
echo -n -e "\e[31mEnter the password for the user $username:\e[0m "
passwd "$username"

##########################################################################

# Install essential packages and desktop environment
pacman -S base-devel dosfstools grub efibootmgr gnome gnome-tweaks lvm2 mtools neovim networkmanager openssh sudo --noconfirm

sleep 1

clear

# Enable SSH service
systemctl enable sshd

##########################################################################

# Install the kernel and related packages
pacman -S linux linux-headers linux-lts linux-lts-headers --noconfirm

# Install firmware packages
pacman -S linux-firmware --noconfirm

clear
##########################################################################

# Ask the user about their GPU (Intel or Nvidia)
while true; do
    echo -n -e "\e[31mDo you have an Intel or Nvidia GPU? (intel/nvidia):\e[0m "
    read gpu_choice

    if [[ "$gpu_choice" == "intel" ]]; then
        # Install Intel GPU drivers
        pacman -S mesa --noconfirm
        pacman -S intel-media-driver --noconfirm
        echo -e "\e[31mIntel GPU drivers installed.\e[0m"
        break
    elif [[ "$gpu_choice" == "nvidia" ]]; then
        # Install Nvidia GPU drivers
        pacman -S nvidia nvidia-utils nvidia-lts --noconfirm
        echo -e "\e[31mNvidia GPU drivers installed.\e[0m"
        break
    else
        echo -e "\e[31mInvalid choice for GPU. Please enter 'intel' or 'nvidia'.\e[0m"
    fi
done


clear

##########################################################################

# Modify /etc/mkinitcpio.conf to add "encrypt" and "lvm2" in the HOOKS line
echo -e "\e[31mModifying /etc/mkinitcpio.conf to include 'encrypt' and 'lvm2' in HOOKS...\e[0m"

# Backup the original mkinitcpio.conf before modifying
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak

# Use sed to insert "encrypt" and "lvm2" between "block" and "filesystems" in the HOOKS line
sed -i 's/\(HOOKS=\([^\)]*\)block\)/\1 encrypt lvm2/' /etc/mkinitcpio.conf

echo -e "\e[31mUpdated HOOKS line:\e[0m"
grep "^HOOKS=" /etc/mkinitcpio.conf

##########################################################################

# Regenerate initramfs for both linux and linux-lts kernels
echo -e "\e[31mRegenerating initramfs for linux and linux-lts kernels...\e[0m"

mkinitcpio -p linux
mkinitcpio -p linux-lts


clear
##########################################################################

# Modify /etc/locale.gen to uncomment the desired locales (en_US.UTF-8 and de_DE.UTF-8)
echo -e "\e[31mModifying /etc/locale.gen to enable 'en_US.UTF-8' and 'de_DE.UTF-8' locales...\e[0m"

# Uncomment en_US.UTF-8 and de_DE.UTF-8 lines in /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#de_DE.UTF-8/de_DE.UTF-8/' /etc/locale.gen

# Verify the modification
echo -e "\e[31mUpdated /etc/locale.gen:\e[0m"
grep -E "en_US.UTF-8|de_DE.UTF-8" /etc/locale.gen

##########################################################################

# Generate the locales
echo -e "\e[31mRunning locale-gen...\e[0m"
locale-gen

clear

##########################################################################

# Modify /etc/default/grub to include cryptdevice option
echo -e "\e[31mModifying /etc/default/grub to include 'cryptdevice=/dev/$partition3:volgroup0'...\e[0m"

# Use sed to add cryptdevice between loglevel=3 and quiet
sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)/\1 cryptdevice=\/dev\/'$partition3':volgroup0 quiet/' /etc/default/grub

# Verify the modification
echo -e "\e[31mUpdated GRUB_CMDLINE_LINUX_DEFAULT:\e[0m"
grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub

##########################################################################

clear

# Create the EFI directory and mount the EFI partition
echo -e "\e[31mCreating /boot/EFI and mounting the EFI partition...\e[0m"

systemctl daemon-reload

mount "${partition_prefix}1" /boot/EFI

# Install GRUB for UEFI systems
echo -e "\e[31mInstalling GRUB for UEFI...\e[0m"
if ! grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck; then
    echo -e "\e[31mGRUB installation failed. Exiting.\e[0m"
    exit 1
fi


clear
##########################################################################

# Copy GRUB locale files for English and German
echo -e "\e[31mCopying GRUB locale files...\e[0m"

# For English locale
cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo

# For German locale
cp /usr/share/locale/de\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/de.mo

##########################################################################

# Regenerate GRUB configuration file
echo -e "\e[31mRegenerating GRUB configuration file...\e[0m"
grub-mkconfig -o /boot/grub/grub.cfg

clear
##########################################################################

# Enable necessary system services
echo -e "\e[31mEnabling GDM (GNOME Display Manager) and NetworkManager...\e[0m"
systemctl enable gdm
systemctl enable NetworkManager

clear
##########################################################################

# Exit the chroot environment
echo -e "\e[31mExiting chroot environment...\e[0m"
exit 0

##########################################################################

# Verify the modification