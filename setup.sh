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
echo -e "\e[31mEnter the device identifier (e.g., sda, nvme0n1):\e[0m "
read device
echo "You entered device: $device"

selected_device="/dev/$device"

# Check if the selected device exists and is a block device
if [ ! -b "$selected_device" ]; then
    echo "Invalid device selected. Exiting..."
    exit 1
fi

echo -e "\e[31mWarning: Partitioning will destroy data on $selected_device. Are you sure you want to continue? (y/n)\e[0m"
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

clear

echo "Filesystems created: FAT32 on ${partition_prefix}1 and EXT4 on ${partition_prefix}2."

##########################################################################

partition3="${partition_prefix}3"

# LUKS encryption on partition 3
echo -n -e "\e[31mEnter passphrase for LUKS encryption:\e[0m "
echo
read -s passphrase
echo -n -e "\e[31mEnter passphrase again:\e[0m "
echo
read -s passphrase2

if [ "$passphrase" != "$passphrase2" ]; then
    echo "Passphrases do not match. Exiting..."
    exit 1
fi  

echo -n "$passphrase" | cryptsetup luksFormat "$partition3" --batch-mode

# Open the LUKS partition
echo -n "$passphrase" | cryptsetup open --type luks "$partition3" lvm

# Create physical volume
pvcreate /dev/mapper/lvm

# Create volume group
vgcreate volgroup0 /dev/mapper/lvm

# Create logical volume for root (user input or default 30GB)
# Default values for logical volumes

# Prompt for lv_root size with default value
echo -n -e "\e[31mEnter size for lv_root (e.g., 30G for 30GB, press Enter for default 30GB):\e[0m "
read lv_root_size
if [ -z "$lv_root_size" ]; then
    lv_root_size="30G"
fi

# Prompt for lv_home size with default value
echo -n -e "\e[31mEnter size for lv_home (e.g., 200G for 200GB, press Enter for default 200GB):\e[0m "
read lv_home_size
if [ -z "$lv_home_size" ]; then
    lv_home_size="200G"
fi


# Create logical volume for root
lvcreate -L "$lv_root_size" volgroup0 -n lv_root
if [ $? -ne 0 ]; then
    echo "Failed to create logical volume for root. Exiting..."
    exit 1
fi

# Create logical volume for home
lvcreate -L "$lv_home_size" volgroup0 -n lv_home
if [ $? -ne 0 ]; then
    echo "Failed to create logical volume for home. Exiting..."
    exit 1
fi

echo "Logical volumes created successfully!"


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

# Check that the volume group exists
vgdisplay volgroup0 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Volume group 'volgroup0' does not exist. Exiting..."
    exit 1
fi

# Check that the logical volumes exist
lvdisplay /dev/volgroup0/lv_root > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Logical volume '/dev/volgroup0/lv_root' does not exist. Exiting..."
    exit 1
fi

lvdisplay /dev/volgroup0/lv_home > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Logical volume '/dev/volgroup0/lv_home' does not exist. Exiting..."
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
pacstrap /mnt base

echo "Base system installation complete."

##########################################################################

# Generate fstab file for the newly mounted system
genfstab -U -p /mnt >> /mnt/etc/fstab

systemctl daemon-reload

clear

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

curl -o /mnt/chroot.sh https://raw.githubusercontent.com/Trivaris/Arch/refs/heads/main/chroot.sh
chmod +x /mnt/chroot.sh

# Chroot into the new system
arch-chroot /mnt sh ./chroot.sh "$partition_prefix"

# Unmount all the filesystems
echo "Unmounting all filesystems..."
umount -a

##########################################################################

# Final message to the user
echo "The script has finished successfully."
echo "Please reboot your system now."