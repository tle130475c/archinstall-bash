#!/usr/bin/env bash

set -euo pipefail

path_to_iso=""
read -e -p "Enter the path to Windows ISO file: " path_to_iso

# Get output ISO details
output_path=$(dirname "$path_to_iso")/$(basename -s .iso "$path_to_iso")_modified.iso
output_volume_name=$(iso-info "$path_to_iso" | grep -i '^Volume[ ]*:' | cut -d':' -f2 | sed 's/^ //g')

# Mount the ISO
sudo mount $path_to_iso /mnt -o loop
mkdir -p /tmp/modified/sources

# Add necessary configuration for Windows Pro
ei_cfg=$(cat <<EOF
[EditionID]
Pro
[Channel]
_Default
[VL]
0
EOF
)

pid_txt=$(cat <<EOF
[PID]
Value=VK7JG-NPHTM-C97JM-9MPGT-3V66T
EOF
)

printf "$ei_cfg" > /tmp/modified/sources/ei.cfg
printf "$pid_txt" > /tmp/modified/sources/pid.txt

# Making the modified ISO
mkisofs \
    -iso-level 4 \
    -l \
    -R \
    -UDF \
    -D \
    -b boot/etfsboot.com \
    -no-emul-boot \
    -boot-load-size 8 \
    -hide boot.catalog \
    -eltorito-alt-boot \
    -eltorito-platform efi \
    -no-emul-boot \
    -b efi/microsoft/boot/efisys.bin \
    -V $output_volume_name \
    -o $output_path \
    /mnt \
    /tmp/modified

sudo umount /mnt
rm -rf /tmp/modified
