#!/bin/bash

# Try to ping Google's DNS server to check internet connection
ping -c 3 8.8.8.8 &>/dev/null

# Check if the ping command was successful
if [ $? -ne 0 ]; then
    echo "The system is not connected to the internet. Exiting..."
    exit 1
else
    echo "The system is connected to the internet."
fi

##########################################################################

echo "Available devices:"
lsblk -d -n -o NAME,SIZE,MODEL

# Prompt user to select a device
echo "Enter the device identifier (e.g., sda, nvme0n1): "
read device
selected_device="/dev/$device"

# Check if the selected device exists and is a block device
if [ ! -b "$selected_device" ]; then
    echo "Invalid device selected. Exiting..."
    exit 1
fi

echo "Warning: Partitioning will destroy data on $selected_device. Are you sure you want to continue? (y/n)"
read confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborting partitioning."
    exit 1
fi

# Partition the disk with fdisk
echo -e "g\nn\n\n\n+1G\nn\n\n\n+1G\nn\n\n\n\n\nt\n3\n44\nw" | fdisk "$selected_device"


##########################################################################

# Check if the device is NVMe and adjust partition names
if [[ "$selected_device" =~ ^/dev/nvme ]]; then
    partition_prefix="${selected_device}p"
else
    partition_prefix="${selected_device}"
fi


# Create FAT32 filesystem on partition 1
mkfs.fat -F32 "${partition_prefix}1"

# Create EXT4 filesystem on partition 2
mkfs.ext4 "${partition_prefix}2"

echo "Filesystems created: FAT32 on ${partition_prefix}1 and EXT4 on ${partition_prefix}2."

# Device and partition setup (assuming partition naming logic from previous steps)
if [[ "$selected_device" =~ ^/dev/nvme ]]; then
    partition_prefix="${selected_device}p"
else
    partition_prefix="${selected_device}"
fi

##########################################################################

partition3="${partition_prefix}3"

# LUKS encryption on partition 3
echo -n "Enter passphrase for LUKS encryption: "
read -s passphrase
echo -n "$passphrase" | cryptsetup luksFormat "$partition3" --batch-mode

# Open the LUKS partition
echo -n "$passphrase" | cryptsetup open --type luks "$partition3" lvm

# Create physical volume
pvcreate /dev/mapper/lvm

# Create volume group
vgcreate volgroup0 /dev/mapper/lvm

# Create logical volume for root (user input or default 30GB)
echo -n "Enter size for lv_root (e.g., 30G for 30GB, press Enter for default 30GB): "
read lv_root_size
# Calculate remaining space after allocating lv_root
total_space=$(vgs --noheadings -o vg_size --units G volgroup0)
lv_root_size=${lv_root_size:-30G}
remaining_space=$(echo "$total_space - $lv_root_size" | bc)

lvcreate -L "$lv_root_size" volgroup0 -n lv_root
if [ $? -ne 0 ]; then
    echo "Failed to create logical volume for root. Exiting..."
    exit 1
fi

lvcreate -L "$remaining_space" volgroup0 -n lv_home


# Store the device and volume names in variables
lv_root="/dev/volgroup0/lv_root"
lv_home="/dev/volgroup0/lv_home"
volgroup0="volgroup0"
lvm="/dev/mapper/lvm"

echo "LVM setup complete:"
echo "Physical volume: /dev/mapper/lvm"
echo "Volume group: $volgroup0"
echo "Logical volume for root: $lv_root"
echo "Logical volume for home: $lv_home"

##########################################################################

#!/bin/bash

# Check that the volume group exists
vgdisplay volgroup0 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Volume group 'volgroup0' does not exist. Exiting..."
    exit 1
fi

# Check that the logical volumes exist
lvdisplay "$lv_root" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Logical volume '$lv_root' does not exist. Exiting..."
    exit 1
fi

lvdisplay "$lv_home" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Logical volume '$lv_home' does not exist. Exiting..."
    exit 1
fi

echo "Volume group and logical volumes are correctly created:"
echo "Volume group: volgroup0"
echo "Logical volume for root: $lv_root"
echo "Logical volume for home: $lv_home"

##########################################################################

# Load necessary kernel module for LVM
modprobe dm_mod

# Scan for volume groups
vgscan

# Activate the volume group
vgchange -ay

##########################################################################

# Create EXT4 filesystems on the logical volumes
mkfs.ext4 /dev/volgroup0/lv_root
mkfs.ext4 /dev/volgroup0/lv_home

echo "Filesystems created: EXT4 on lv_root and lv_home."

##########################################################################

# Mount the root logical volume
mount /dev/volgroup0/lv_root /mnt

# Create and mount boot directory (assuming partition2 is the boot partition)
mkdir /mnt/boot
mount "${partition_prefix}2" /mnt/boot

echo "Mounted boot partition: ${partition_prefix}2"

# Create and mount home directory
mkdir /mnt/home
mount /dev/volgroup0/lv_home /mnt/home

echo "Mounted home logical volume: /dev/volgroup0/lv_home"

##########################################################################

# Install the base system using pacstrap
pacstrap -i /mnt base --no-confirm

echo "Base system installation complete."

##########################################################################

# Generate fstab file for the newly mounted system
genfstab -U -p /mnt >> /mnt/etc/fstab

# Display the generated fstab to the user for review
echo "Here is the generated /etc/fstab:"
cat /mnt/etc/fstab

# Ask the user if the fstab looks correct
echo -n "Does the /etc/fstab file look correct? (y/n): "
read fstab_confirm

if [[ "$fstab_confirm" != "y" && "$fstab_confirm" != "Y" ]]; then
    echo "Aborting. Please check the /etc/fstab file and try again."
    exit 1
fi

echo "Proceeding with arch-chroot..."

##########################################################################

# Chroot into the new system
arch-chroot /mnt

##########################################################################

# Set the root password
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
pacman -S base-devel dosfstools grub efibootmgr gnome gnome-tweaks lvm2 mtools nvim networkmanager openssh os-prober sudo --noconfirm

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
cp /mnt/etc/mkinitcpio.conf /mnt/etc/mkinitcpio.conf.bak

# Use sed to insert "encrypt" and "lvm2" between "block" and "filesystems" in the HOOKS line
sed -i 's/\(HOOKS=\([^\)]*\)block\)/\1 encrypt lvm2/' /mnt/etc/mkinitcpio.conf

# Verify the modification
echo "Updated HOOKS line:"
grep "^HOOKS=" /mnt/etc/mkinitcpio.conf

##########################################################################

# Regenerate initramfs for both linux and linux-lts kernels
echo "Regenerating initramfs for linux and linux-lts kernels..."

arch-chroot /mnt mkinitcpio -p linux
arch-chroot /mnt mkinitcpio -p linux-lts

##########################################################################

# Modify /etc/locale.gen to uncomment the desired locales (en_US.UTF-8 and de_DE.UTF-8)
echo "Modifying /etc/locale.gen to enable 'en_US.UTF-8' and 'de_DE.UTF-8' locales..."

# Uncomment en_US.UTF-8 and de_DE.UTF-8 lines in /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /mnt/etc/locale.gen
sed -i 's/^#de_DE.UTF-8/de_DE.UTF-8/' /mnt/etc/locale.gen

# Verify the modification
echo "Updated /etc/locale.gen:"
grep -E "en_US.UTF-8|de_DE.UTF-8" /mnt/etc/locale.gen

##########################################################################

# Generate the locales
echo "Running locale-gen..."
arch-chroot /mnt locale-gen

##########################################################################

# Modify /etc/default/grub to include cryptdevice option
echo "Modifying /etc/default/grub to include 'cryptdevice=/dev/partition3:volgroup0'..."

# Use sed to add cryptdevice between loglevel=3 and quiet
sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)/\1 cryptdevice=\/dev\/partition3:volgroup0/' /mnt/etc/default/grub

# Verify the modification
echo "Updated GRUB_CMDLINE_LINUX_DEFAULT:"
grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /mnt/etc/default/grub

##########################################################################

# Create the EFI directory and mount the EFI partition
echo "Creating /boot/EFI and mounting the EFI partition..."

mkdir -p /mnt/boot/EFI
mount "${partition_prefix}1" /mnt/boot/EFI

# Install GRUB for UEFI systems
echo "Installing GRUB for UEFI..."
arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck

##########################################################################

# Copy GRUB locale files for English and German
echo "Copying GRUB locale files..."

# For English locale
cp /mnt/usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /mnt/boot/grub/locale/en.mo

# For German locale
cp /mnt/usr/share/locale/de\@quot/LC_MESSAGES/grub.mo /mnt/boot/grub/locale/de.mo

##########################################################################

# Regenerate GRUB configuration file
echo "Regenerating GRUB configuration file..."
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

##########################################################################

# Enable necessary system services
echo "Enabling GDM (GNOME Display Manager) and NetworkManager..."
arch-chroot /mnt systemctl enable gdm
arch-chroot /mnt systemctl enable NetworkManager

##########################################################################

# Exit the chroot environment
echo "Exiting chroot environment..."
exit

##########################################################################

# Unmount all the filesystems
echo "Unmounting all filesystems..."
umount -a

##########################################################################

# Final message to the user
echo "The script has finished successfully."
echo "Please reboot your system now."