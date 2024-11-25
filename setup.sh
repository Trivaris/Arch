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

while true; do
    echo -e "\e[31mEnter the device identifier (e.g., sda, nvme0n1):\e[0m "
    read device
    echo "You entered device: $device"
    selected_device="/dev/$device"

    if [ ! -b "$selected_device" ]; then
        echo "Invalid device. Try again."
    else
        break
    fi
done

if [[ "$selected_device" =~ ^/dev/nvme ]]; then
    partition_prefix="${selected_device}p"
else
    partition_prefix="${selected_device}"
fi
partition1="${partition_prefix}1"
partition2="${partition_prefix}2"
partition3="${partition_prefix}3"
echo "You entered device: $selected_device"
echo "You entered partition1: $partition1"
echo "You entered partition2: $partition2"
echo "You entered partition3: $partition3"

sleep 5

echo -e "\e[31mWhats your Passphrase?\e[0m"
echo
read passphrase
echo -n -e "\e[31mEnter passphrase again:\e[0m "
echo
read -s passphrase2

while true; do
    if [ "$passphrase" != "$passphrase2" ]; then
        echo "Passphrases do not match. Try again."
    else
        break
    fi
done
volgroup0="volgroup0"
lv_root="lv_root"
lv_home="lv_home"
lvm="/dev/mapper/lvm"

echo -e "\e[31mWarning: Partitioning will permanently delete all data on $selected_device. Are you sure you want to continue? (y/n)\e[0m"
read confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborting partitioning."
    exit 1
fi

# Partition the disk with fdisk
echo -e "g\nn\n\n\n+1G\nn\n\n\n+1G\nn\n\n\n\n\nt\n3\n44\nw" | fdisk "$selected_device"

clear

echo -e "p" | fdisk "$selected_device"

sleep 10

mkfs.fat -F32 "$partition1"
mkfs.ext4 "$partition2"

clear

echo "Filesystems created: FAT32 on ${partition1} and EXT4 on ${partition2}."

##########################################################################



echo -e "\e[31mEncrypting $partition3...\e[0m"
echo -n "$passphrase" | cryptsetup luksFormat "$partition3" --batch-mode
echo -n "$passphrase" | cryptsetup open --type luks "$partition3" lvm

pvcreate "$lvm"
vgcreate "$volgroup0" "$lvm"

read -p $'\e[31mEnter size for lv_root (press Enter for default 30GB):\e[0m ' lv_root_size
lv_root_size=${lv_root_size:-30GB}

read -p $'\e[31mEnter size for lv_home (press Enter for default 200GB):\e[0m ' lv_home_size
lv_home_size=${lv_home_size:-200GB}

create_lv() {
    lvcreate -L "$1" "$volgroup0" -n "$2" || { 
        echo "Failed to create logical volume for $2. Exiting..."; 
        exit 1; 
    }
}

create_lv "$lv_root_size" "$lv_root"
create_lv "$lv_home_size" "$lv_home"

echo "Logical volumes created successfully!"

echo "LVM setup complete:"
echo "Physical volume: $lvm"
echo "Volume group: $volgroup0"
echo "Logical volume for root: $lv_root"
echo "Logical volume for home: $lv_home"

sleep 10

##########################################################################

check_exists() {
    $1 > /dev/null 2>&1 || { 
        echo "Error: $2. Exiting..."; 
        exit 1; 
    }
}

check_exists "vgdisplay $volgroup0" "Volume group '$volgroup0' does not exist"
check_exists "lvdisplay /dev/volgroup0/lv_root" "Logical volume '$lv_root' does not exist"
check_exists "lvdisplay /dev/volgroup0/lv_home" "Logical volume '$lv_home' does not exist"

echo "Volume group and logical volumes are correctly created:"
echo "Volume group: $volgroup0"
echo "Logical volume for root: $lv_root"
echo "Logical volume for home: $lv_home"

sleep 10

modprobe dm_mod
vgscan
vgchange -ay

mkfs.ext4 "$lv_root"
mkfs.ext4 "$lv_home"

echo "Filesystems created: EXT4 on $lv_root and $lv_home."

sleep 10

mount "$lv_root" /mnt

mkdir /mnt/boot
mount "$partition2" /mnt/boot

mkdir /mnt/home
mount "$lv_home" /mnt/home

echo "Mounted home logical volume: $lv_home"

sleep 10

pacstrap /mnt base
echo "Base system installation complete."

sleep 10

genfstab -U -p /mnt >> /mnt/etc/fstab
clear

echo "Here is the generated /etc/fstab:"
cat /mnt/etc/fstab

echo -n "Does the /etc/fstab file look correct? (y/n): "
read fstab_confirm

if [[ "$fstab_confirm" != "y" && "$fstab_confirm" != "Y" ]]; then
    echo "Aborting. Please check the /etc/fstab file and try again."
    exit 1
fi

echo "Proceeding with arch-chroot..."

curl -o /mnt/chroot.sh https://raw.githubusercontent.com/Trivaris/Arch/refs/heads/main/chroot.sh
chmod +x /mnt/chroot.sh

mkdir /mnt/boot/EFI

arch-chroot /mnt sh ./chroot.sh "$partition_prefix"

#echo "Unmounting all filesystems..."
#umount -a

echo "The script has finished successfully."
echo "Please reboot your system now."