#!/bin/bash
clear

volgroup0="volgroup0"
lv_root="/dev/"$volgroup0"/lv_root"
lv_home="/dev/"$volgroup0"/lv_home"
lvm="/dev/mapper/lvm"

partition_prefix="${1}"


echo "Volume group and logical volumes are correctly created:"
echo "Volume group: $volgroup0"
echo "Logical volume for root: $lv_root"
echo "Logical volume for home: $lv_home"
echo "Partition prefix: $partition_prefix"

sleep 10

echo -n -e "\e[31mEnter the root password:\e[0m "
echo
passwd

echo -n -e "\e[31mEnter a username to create:\e[0m "
read username
useradd -m -g users -G wheel "$username"

echo -n -e "\e[31mEnter the password for the user $username:\e[0m "
echo
passwd "$username"


pacman -S base-devel dosfstools grub efibootmgr gnome gnome-tweaks lvm2 mtools neovim networkmanager openssh sudo --noconfirm
sleep 1
clear
systemctl enable sshd

pacman -S linux linux-headers linux-lts linux-lts-headers --noconfirm
pacman -S linux-firmware --noconfirm
clear

while true; do
    echo -n -e "\e[31mDo you have an Intel or Nvidia GPU? (intel/nvidia):\e[0m "
    read gpu_choice

    if [[ "$gpu_choice" == "intel" ]]; then
        pacman -S mesa --noconfirm
        pacman -S intel-media-driver --noconfirm
        echo -e "\e[31mIntel GPU drivers installed.\e[0m"
        break
    elif [[ "$gpu_choice" == "nvidia" ]]; then
        pacman -S nvidia nvidia-utils nvidia-lts --noconfirm
        echo -e "\e[31mNvidia GPU drivers installed.\e[0m"
        break
    else
        echo -e "\e[31mInvalid choice for GPU. Please enter 'intel' or 'nvidia'.\e[0m"
    fi
done
clear

echo -e "\e[31mModifying /etc/mkinitcpio.conf to include 'encrypt' and 'lvm2' in HOOKS...\e[0m"
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
sed -i 's/\(HOOKS=\([^\)]*\)block\)/\1 encrypt lvm2/' /etc/mkinitcpio.conf
echo -e "\e[31mUpdated HOOKS line:\e[0m"
grep "^HOOKS=" /etc/mkinitcpio.conf

echo -e "\e[31mRegenerating initramfs for linux and linux-lts kernels...\e[0m"

mkinitcpio -p linux
mkinitcpio -p linux-lts


clear

echo -e "\e[31mModifying /etc/locale.gen to enable 'en_US.UTF-8' and 'de_DE.UTF-8' locales...\e[0m"

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#de_DE.UTF-8/de_DE.UTF-8/' /etc/locale.gen

echo -e "\e[31mUpdated /etc/locale.gen:\e[0m"
grep -E "en_US.UTF-8|de_DE.UTF-8" /etc/locale.gen

echo -e "\e[31mRunning locale-gen...\e[0m"
locale-gen

clear

echo -e "\e[31mModifying /etc/default/grub"

sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)/\1 cryptdevice='${partition_prefix}3':'$volgroup0' quiet/' /etc/default/grub

echo -e "\e[31mUpdated GRUB_CMDLINE_LINUX_DEFAULT:\e[0m"
grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub

sleep 10
clear

echo -e "\e[31mCreating /boot/EFI and mounting the EFI partition...\e[0m"

mount "${partition_prefix}1" /boot/EFI

echo -e "\e[31mInstalling GRUB for UEFI...\e[0m"
grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck

echo -e "\e[31mGRUB installed.\e[0m"
sleep 5

clear

echo -e "\e[31mCopying GRUB locale files...\e[0m"

cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
cp /usr/share/locale/de/LC_MESSAGES/grub.mo /boot/grub/locale/de.mo

echo -e "\e[31mRegenerating GRUB configuration file...\e[0m"
grub-mkconfig -o /boot/grub/grub.cfg

clear

echo -e "\e[31mEnabling GDM (GNOME Display Manager) and NetworkManager...\e[0m"
systemctl enable gdm
systemctl enable NetworkManager

clear

echo -e "\e[31mExiting chroot environment...\e[0m"
exit 0