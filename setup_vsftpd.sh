#!/usr/bin/env bash

set -euo pipefail

VSFTPD_CONF="/etc/vsftpd.conf"

sudo pacman -Syu --needed --noconfirm vsftpd

# Backup existing configuration
sudo cp "$VSFTPD_CONF" "$VSFTPD_CONF.bak"

sudo sed -i 's/^#write_enable=YES/write_enable=YES/' "$VSFTPD_CONF"
sudo sed -i 's/^#local_enable=YES/local_enable=YES/' "$VSFTPD_CONF"
sudo sed -i 's/^#chroot_local_user=YES/chroot_local_user=YES/' "$VSFTPD_CONF"

printf "\nlocal_root=/home/$USER/ftp_root\n" | sudo tee -a "$VSFTPD_CONF"

mkdir -p "/home/$USER/ftp_root/upload"
sudo chmod 550 "/home/$USER/ftp_root"
sudo chmod 750 "/home/$USER/ftp_root/upload"
sudo chown -R "$USER:$USER" "/home/$USER/ftp_root"

sudo systemctl enable --now vsftpd.service