#!/usr/bin/env bash

set -e

root_password="<root_password>"
username="<username>"
realname="<realname>"
user_password="<user_password>"
hostname="<hostname>"

wifi_ssid="<wifi_ssid>"
wifi_password="<wifi_password>"

luks_password="<luks_password>"

# Connect to Wifi
ping -c 3 8.8.8.8
if [ $? -ne 0 ]; then
    iwctl --passphrase="$wifi_password" station wlan0 connect "$wifi_ssid"
    sleep 10
fi

# Waiting for keyring to be initialized
systemctl start archlinux-keyring-wkd-sync.timer
sleep 30

# Disable auto-generate mirrorlist
systemctl disable --now reflector.timer
systemctl disable --now reflector.service

# Enable network time synchronization
timedatectl set-ntp true

# Configure mirrorlist
printf "Server = https://mirror.xtom.com.hk/archlinux/\$repo/os/\$arch\n" > /etc/pacman.d/mirrorlist
printf "Server = https://arch-mirror.wtako.net/\$repo/os/\$arch\n" >> /etc/pacman.d/mirrorlist
printf "Server = https://mirror-hk.koddos.net/archlinux/\$repo/os/\$arch\n" >> /etc/pacman.d/mirrorlist

# Create partitions
sgdisk -Z /dev/nvme0n1
wipefs -a /dev/nvme0n1
sgdisk -n 0:0:+550M -t 0:ef00 -c 0:esp /dev/nvme0n1
wipefs -a /dev/nvme0n1p1
sgdisk -n 0:0:+550M -t 0:ea00 -c 0:XBOOTLDR /dev/nvme0n1
wipefs -a /dev/nvme0n1p2
sgdisk -n 0:0:0 -t 0:8309 -c 0:luks-encrypted /dev/nvme0n1
wipefs -a /dev/nvme0n1p3
printf "$luks_password" | cryptsetup luksFormat --type luks2 /dev/nvme0n1p3 -
printf "$luks_password" | cryptsetup open /dev/nvme0n1p3 encrypt-lvm -
wipefs -a /dev/mapper/encrypt-lvm
pvcreate /dev/mapper/encrypt-lvm
vgcreate vg-system /dev/mapper/encrypt-lvm
lvcreate -L 48G vg-system -n swap
lvcreate -l +100%FREE vg-system -n root
mkfs.vfat -F32 /dev/nvme0n1p1
mkfs.vfat -F32 /dev/nvme0n1p2
mkswap /dev/vg-system/swap
mkfs.ext4 /dev/vg-system/root
mount /dev/vg-system/root /mnt
mkdir -p /mnt/efi
mount /dev/nvme0n1p1 /mnt/efi
mkdir -p /mnt/boot
mount /dev/nvme0n1p2 /mnt/boot
swapon /dev/vg-system/swap

# Install essential packages
pacstrap /mnt base base-devel linux linux-headers linux-firmware man-pages man-db iptables-nft pipewire pipewire-pulse pipewire-alsa alsa-utils gst-plugin-pipewire wireplumber bash-completion nfs-utils gvim linux-lts linux-lts-headers

# Disable makepkg debug
linum=$(arch-chroot /mnt sed -n "/^OPTIONS=(.*)$/=" /etc/makepkg.conf)
arch-chroot /mnt sed -i "${linum}s/debug/\!debug/" /etc/makepkg.conf

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configure time zone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Ho_Chi_Minh /etc/localtime
arch-chroot /mnt hwclock --systohc

# Configure localization
printf "en_US.UTF-8 UTF-8\n" > /mnt/etc/locale.gen
printf "LANG=en_US.UTF-8\n" > /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

# Configure repository for 64-bit system
linum=$(arch-chroot /mnt sed -n "/\\[multilib\\]/=" /etc/pacman.conf)
arch-chroot /mnt sed -i "${linum}s/^#//" /etc/pacman.conf
((linum++))
arch-chroot /mnt sed -i "${linum}s/^#//" /etc/pacman.conf

# Configure network
printf "$hostname\n" > /mnt/etc/hostname
printf "127.0.0.1\tlocalhost\n" > /mnt/etc/hosts
printf "::1\tlocalhost\n" >> /mnt/etc/hosts
printf "127.0.1.1\t%s.localdomain\t%s\n" "$hostname" "$hostname" >> /mnt/etc/hosts
arch-chroot /mnt pacman -Syu --needed --noconfirm networkmanager
arch-chroot /mnt systemctl enable NetworkManager.service

# Set root password
printf "%s\n%s\n" "$root_password" "$root_password" | arch-chroot /mnt passwd

# Create a new user
arch-chroot /mnt useradd -G wheel,audio,lp,optical,storage,disk,video,power -s /bin/bash -m $username -d /home/$username -c "$realname"
printf "%s\n%s\n" "$user_password" "$user_password" | arch-chroot /mnt passwd $username

# Disable sudo password prompt timeout
printf "\n## Disable password prompt timeout\n" >> /mnt/etc/sudoers
printf "Defaults passwd_timeout=0\n" >> /mnt/etc/sudoers

# Disable sudo timestamp timeout
printf "\n## Disable sudo timestamp timeout\n" >> /mnt/etc/sudoers
printf "Defaults timestamp_timeout=-1\n" >> /mnt/etc/sudoers

# Configure mkinitcpio
arch-chroot /mnt pacman -Syu --needed --noconfirm lvm2
linum=$(arch-chroot /mnt sed -n "/^HOOKS=(.*)$/=" /etc/mkinitcpio.conf)
arch-chroot /mnt sed -i "${linum}s/filesystems/filesystems resume/" /etc/mkinitcpio.conf
arch-chroot /mnt sed -i "${linum}s/block/block encrypt lvm2/" /etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux

# Configure systemd-boot loader
loader_filename="/mnt/efi/loader/loader.conf"
arch-chroot /mnt pacman -Syu --needed --noconfirm efibootmgr intel-ucode
arch-chroot /mnt bootctl --esp-path=/efi --boot-path=/boot install
printf "default archlinux\n" > $loader_filename
printf "timeout 5\n" >> $loader_filename
printf "console-mode keep\n" >> $loader_filename
printf "editor no\n" >> $loader_filename

# Add systemd-boot boot entries
boot_entry_filename="/mnt/boot/loader/entries/archlinux.conf"
printf "title Arch Linux\n " > $boot_entry_filename
printf "linux /vmlinuz-linux\n" >> $boot_entry_filename
printf "initrd /intel-ucode.img\n" >> $boot_entry_filename
printf "initrd /initramfs-linux.img\n" >> $boot_entry_filename
printf "options cryptdevice=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3):encrypt-lvm root=/dev/vg-system/root resume=UUID=$(blkid -s UUID -o value /dev/vg-system/swap) rw\n" >> $boot_entry_filename

# Temporarily allow members of wheel group to execute any command without password
linum=$(arch-chroot /mnt sed -n "/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL$/=" /etc/sudoers)
arch-chroot /mnt sed -i "${linum}s/^# //" /etc/sudoers

# Install Yay AUR helper
arch-chroot /mnt pacman -Syu --needed --noconfirm go

run_command_as_user() {
    local command="$1"
    arch-chroot -u "$username" /mnt bash -c "export HOME=/home/$username && $command"
}

run_command_as_user "mkdir /home/$username/tmp"
run_command_as_user "curl -LJo /home/$username/tmp/yay.tar.gz https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz"
run_command_as_user "tar -xvf /home/$username/tmp/yay.tar.gz -C /home/$username/tmp"
run_command_as_user "export GOCACHE='/home/$username/.cache/go-build' && cd /home/$username/tmp/yay && makepkg -sri --noconfirm"

# Install KVM
arch-chroot /mnt pacman -Syu --needed --noconfirm virt-manager qemu-full vde2 dnsmasq bridge-utils virt-viewer dmidecode edk2-ovmf iptables-nft swtpm qemu-hw-usb-host qemu-block-gluster qemu-block-iscsi

arch-chroot /mnt systemctl enable libvirtd.service

libvirtd_conf_file="/etc/libvirt/libvirtd.conf"
linum=$(arch-chroot /mnt sed -n "/^#unix_sock_group = \"libvirt\"$/=" $libvirtd_conf_file)
arch-chroot /mnt sed -i "${linum}s/^#//" $libvirtd_conf_file
linum=$(arch-chroot /mnt sed -n "/^#unix_sock_rw_perms = \"0770\"$/=" $libvirtd_conf_file)
arch-chroot /mnt sed -i "${linum}s/^#//" $libvirtd_conf_file

arch-chroot /mnt usermod -a -G libvirt $username
arch-chroot /mnt usermod -a -G kvm $username

# Install Intel packages
arch-chroot /mnt pacman -Syu --needed --noconfirm mesa lib32-mesa ocl-icd lib32-ocl-icd intel-compute-runtime vulkan-intel lib32-vulkan-intel vulkan-icd-loader lib32-vulkan-icd-loader intel-media-driver vpl-gpu-rt libva-utils intel-media-sdk sof-firmware

# Install pipewire
arch-chroot /mnt pacman -Syu --needed --noconfirm pipewire pipewire-audio pipewire-pulse pipewire-alsa alsa-utils gst-plugin-pipewire lib32-pipewire wireplumber

# Install Thermald
arch-chroot /mnt pacman -Syu --needed --noconfirm thermald
arch-chroot /mnt systemctl enable thermald.service

# Install GNOME Desktop Environment
arch-chroot /mnt pacman -Syu --needed --noconfirm xorg-server baobab eog evince file-roller gdm gnome-calculator gnome-calendar gnome-clocks gnome-color-manager gnome-control-center gnome-font-viewer gnome-keyring gnome-screenshot gnome-shell-extensions gnome-system-monitor gnome-terminal gnome-themes-extra gnome-video-effects nautilus sushi gnome-tweaks totem xdg-user-dirs-gtk gnome-usage endeavour dconf-editor gnome-shell-extension-appindicator alacarte gnome-text-editor gnome-sound-recorder seahorse seahorse-nautilus gnome-browser-connector xdg-desktop-portal xdg-desktop-portal-gnome gnome-disk-utility libappindicator-gtk3 transmission-gtk power-profiles-daemon gvfs-smb gvfs-google gvfs-mtp gvfs-nfs gnome-logs evolution evolution-ews evolution-on gnome-software gnome-boxes gnome-remote-desktop gnome-connections gedit gedit-plugins
arch-chroot /mnt systemctl enable gdm.service
arch-chroot /mnt systemctl enable bluetooth.service
run_command_as_user "mkdir -p /home/$username/.config/environment.d"

# Disallow members of wheel group to execute any command without password
linum=$(arch-chroot /mnt sed -n "/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL$/=" /etc/sudoers)
arch-chroot /mnt sed -i "${linum}s/^/# /" /etc/sudoers

# Allow members of wheel group to execute any command
linum=$(arch-chroot /mnt sed -n "/^# %wheel ALL=(ALL:ALL) ALL$/=" /etc/sudoers)
arch-chroot /mnt sed -i "${linum}s/^# //" /etc/sudoers
