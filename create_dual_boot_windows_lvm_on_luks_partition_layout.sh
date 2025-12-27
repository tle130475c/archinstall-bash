#!/usr/bin/env bash

set -euo pipefail

source ./system_info.sh

esp_part_num=1
xbootldr_part_num=5
luks_part_num=6

# Create XBOOTLDR partition
sgdisk -n 0:0:+$xbootldr_size -t 0:ea00 -c 0:XBOOTLDR /dev/$disk_name
wipefs -a /dev/${partition_name}${xbootldr_part_num}

# Create LUKS encrypted partition
sgdisk -n 0:0:0 -t 0:8309 -c 0:luks-encrypted /dev/$disk_name
wipefs -a /dev/${partition_name}${luks_part_num}
printf "$luks_password" | cryptsetup luksFormat --type luks2 /dev/${partition_name}${luks_part_num} -

# Create LVM inside LUKS
printf "$luks_password" | cryptsetup open /dev/${partition_name}${luks_part_num} encrypt-lvm -
wipefs -a /dev/mapper/encrypt-lvm
pvcreate /dev/mapper/encrypt-lvm
vgcreate vg-system /dev/mapper/encrypt-lvm
lvcreate -L $swap_size vg-system -n swap
lvcreate -l +100%FREE vg-system -n root

# Format partitions
mkfs.vfat -F32 /dev/${partition_name}${xbootldr_part_num}
mkswap /dev/vg-system/swap
mkfs.ext4 /dev/vg-system/root

# Mount partitions
mount /dev/vg-system/root /mnt
mkdir -p /mnt/efi
mount /dev/${partition_name}${esp_part_num} /mnt/efi
mkdir -p /mnt/boot
mount /dev/${partition_name}${xbootldr_part_num} /mnt/boot
swapon /dev/vg-system/swap
