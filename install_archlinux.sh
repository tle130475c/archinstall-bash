#!/usr/bin/env bash

set -euo pipefail

source ./system_info.sh

run_command_as_user() {
    local command="$1"
    arch-chroot -u "$username" /mnt bash -c "export HOME=/home/$username && $command"
}

retry() {
    local max_attempts=5
    local delay=30
    local attempt=1
    while true; do
        "$@" && return 0
        if ((attempt >= max_attempts)); then
            printf "Command failed after %d attempts: %s\n" "$max_attempts" "$*" >&2
            return 1
        fi
        printf "Attempt %d/%d failed. Retrying in %ds...\n" "$attempt" "$max_attempts" "$delay" >&2
        ((attempt++))
        sleep "$delay"
    done
}

retry_as_user() {
    retry run_command_as_user "$1"
}

# ── Logging setup ─────────────────────────────────────────────────────────────
# Write to live env /root/ from the start (always writable).
# On exit (success or failure), copy to the installed system if /mnt/root/ exists.
LOG_FILE="/root/archinstall_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
log() { printf "\n[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
trap 'printf "[%s] FAILED at line %d: %s\n" "$(date +"%Y-%m-%d %H:%M:%S")" "$LINENO" "$BASH_COMMAND"' ERR
trap '[[ -d /mnt/root ]] && cp "$LOG_FILE" /mnt/root/ && printf "\nLog saved to installed system: /root/%s\n" "$(basename "$LOG_FILE")"' EXIT
log "Arch Linux installation started — log file: $LOG_FILE"

log "Waiting for keyring to be initialized"
systemctl start archlinux-keyring-wkd-sync.timer
sleep 30

log "Disabling auto-generate mirrorlist"
systemctl disable --now reflector.timer
systemctl disable --now reflector.service

log "Enabling network time synchronization"
timedatectl set-ntp true

log "Configuring mirrorlist"
printf "Server = https://mirror.xtom.com.hk/archlinux/\$repo/os/\$arch\n" > /etc/pacman.d/mirrorlist
printf "Server = https://arch-mirror.wtako.net/\$repo/os/\$arch\n" >> /etc/pacman.d/mirrorlist
printf "Server = https://mirror-hk.koddos.net/archlinux/\$repo/os/\$arch\n" >> /etc/pacman.d/mirrorlist

log "Creating partition layout"
source ./create_lvm_on_luks_partition_layout.sh

log "Installing essential packages via pacstrap"
retry pacstrap /mnt base base-devel linux linux-headers linux-lts linux-lts-headers linux-zen linux-zen-headers linux-firmware man-pages man-db iptables-nft pipewire pipewire-pulse pipewire-alsa alsa-utils gst-plugin-pipewire wireplumber bash-completion nfs-utils gvim usbutils

log "Disabling makepkg debug"
linum=$(arch-chroot /mnt sed -n "/^OPTIONS=(.*)$/=" /etc/makepkg.conf)
arch-chroot /mnt sed -i "${linum}s/debug/\!debug/" /etc/makepkg.conf

log "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

log "Configuring time zone"
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Ho_Chi_Minh /etc/localtime
arch-chroot /mnt hwclock --systohc

log "Configuring localization"
printf "en_US.UTF-8 UTF-8\n" > /mnt/etc/locale.gen
printf "LANG=en_US.UTF-8\n" > /mnt/etc/locale.conf
printf "KEYMAP=us\n" > /mnt/etc/vconsole.conf
arch-chroot /mnt locale-gen

log "Enabling multilib repository"
linum=$(arch-chroot /mnt sed -n "/\\[multilib\\]/=" /etc/pacman.conf)
arch-chroot /mnt sed -i "${linum}s/^#//" /etc/pacman.conf
((linum++))
arch-chroot /mnt sed -i "${linum}s/^#//" /etc/pacman.conf

log "Configuring network"
printf "$hostname\n" > /mnt/etc/hostname
printf "127.0.0.1\tlocalhost\n" > /mnt/etc/hosts
printf "::1\tlocalhost\n" >> /mnt/etc/hosts
printf "127.0.1.1\t%s.localdomain\t%s\n" "$hostname" "$hostname" >> /mnt/etc/hosts
retry arch-chroot /mnt pacman -Syu --needed --noconfirm networkmanager
arch-chroot /mnt systemctl enable NetworkManager.service

log "Setting root password"
printf "%s\n%s\n" "$root_password" "$root_password" | arch-chroot /mnt passwd

log "Creating user: $username"
arch-chroot /mnt useradd -G wheel,audio,lp,optical,storage,disk,video,power,render -s /bin/bash -m $username -d /home/$username -c "$realname"
printf "%s\n%s\n" "$user_password" "$user_password" | arch-chroot /mnt passwd $username

log "Configuring sudoers"
printf "\n## Disable password prompt timeout\n" >> /mnt/etc/sudoers
printf "Defaults passwd_timeout=0\n" >> /mnt/etc/sudoers
printf "\n## Disable sudo timestamp timeout\n" >> /mnt/etc/sudoers
printf "Defaults timestamp_timeout=-1\n" >> /mnt/etc/sudoers
linum=$(arch-chroot /mnt sed -n "/^# %wheel ALL=(ALL:ALL) ALL$/=" /etc/sudoers)
arch-chroot /mnt sed -i "${linum}s/^# //" /etc/sudoers

log "Configuring mkinitcpio"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm lvm2
linum=$(arch-chroot /mnt sed -n "/^HOOKS=(.*)$/=" /etc/mkinitcpio.conf)
arch-chroot /mnt sed -i "${linum}s/filesystems/filesystems resume/" /etc/mkinitcpio.conf
arch-chroot /mnt sed -i "${linum}s/block/block sd-encrypt lvm2/" /etc/mkinitcpio.conf
arch-chroot /mnt sed -i "${linum}s/keymap //" /etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux

log "Configuring systemd-boot loader"
# Configure systemd-boot loader
loader_filename="/mnt/efi/loader/loader.conf"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm efibootmgr
# retry arch-chroot /mnt pacman -Syu --needed --noconfirm intel-ucode
retry arch-chroot /mnt pacman -Syu --needed --noconfirm amd-ucode
arch-chroot /mnt bootctl --esp-path=/efi --boot-path=/boot install
printf "default archlinux\n" > $loader_filename
printf "timeout 5\n" >> $loader_filename
printf "console-mode keep\n" >> $loader_filename
printf "editor no\n" >> $loader_filename

log "Adding boot entries (linux, linux-lts, linux-zen)"
# Add systemd-boot boot entries
boot_entry_filename="/mnt/boot/loader/entries/archlinux.conf"
printf "title Arch Linux\n " > $boot_entry_filename
printf "linux /vmlinuz-linux\n" >> $boot_entry_filename
# printf "initrd /intel-ucode.img\n" >> $boot_entry_filename
printf "initrd /amd-ucode.img\n" >> $boot_entry_filename
printf "initrd /initramfs-linux.img\n" >> $boot_entry_filename
printf "options rd.luks.name=$(blkid -s UUID -o value /dev/${partition_name}${luks_part_num})=encrypt-lvm root=/dev/vg-system/root resume=UUID=$(blkid -s UUID -o value /dev/vg-system/swap) rw\n" >> $boot_entry_filename

# Add systemd-boot boot entries for LTS kernel
boot_entry_filename="/mnt/boot/loader/entries/archlinux-lts.conf"
printf "title Arch Linux LTS\n " > $boot_entry_filename
printf "linux /vmlinuz-linux-lts\n" >> $boot_entry_filename
# printf "initrd /intel-ucode.img\n" >> $boot_entry_filename
printf "initrd /amd-ucode.img\n" >> $boot_entry_filename
printf "initrd /initramfs-linux-lts.img\n" >> $boot_entry_filename
printf "options rd.luks.name=$(blkid -s UUID -o value /dev/${partition_name}${luks_part_num})=encrypt-lvm root=/dev/vg-system/root resume=UUID=$(blkid -s UUID -o value /dev/vg-system/swap) rw\n" >> $boot_entry_filename

# Add systemd-boot boot entries for Zen kernel
boot_entry_filename="/mnt/boot/loader/entries/archlinux-zen.conf"
printf "title Arch Linux Zen\n " > $boot_entry_filename
printf "linux /vmlinuz-linux-zen\n" >> $boot_entry_filename
# printf "initrd /intel-ucode.img\n" >> $boot_entry_filename
printf "initrd /amd-ucode.img\n" >> $boot_entry_filename
printf "initrd /initramfs-linux-zen.img\n" >> $boot_entry_filename
printf "options rd.luks.name=$(blkid -s UUID -o value /dev/${partition_name}${luks_part_num})=encrypt-lvm root=/dev/vg-system/root resume=UUID=$(blkid -s UUID -o value /dev/vg-system/swap) rw\n" >> $boot_entry_filename

log "Creating UEFI boot entry"
arch-chroot /mnt efibootmgr --create --disk /dev/$disk_name --part $esp_part_num --loader '\EFI\systemd\systemd-bootx64.efi' --label "Linux Boot Manager" --unicode

log "Installing KVM and configuring libvirt"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm virt-manager qemu-full vde2 dnsmasq virt-viewer dmidecode edk2-ovmf iptables-nft swtpm qemu-hw-usb-host qemu-block-gluster qemu-block-iscsi
arch-chroot /mnt systemctl enable libvirtd.service
libvirtd_conf_file="/etc/libvirt/libvirtd.conf"
linum=$(arch-chroot /mnt sed -n "/^#unix_sock_group = \"libvirt\"$/=" $libvirtd_conf_file)
arch-chroot /mnt sed -i "${linum}s/^#//" $libvirtd_conf_file
linum=$(arch-chroot /mnt sed -n "/^#unix_sock_rw_perms = \"0770\"$/=" $libvirtd_conf_file)
arch-chroot /mnt sed -i "${linum}s/^#//" $libvirtd_conf_file
arch-chroot /mnt usermod -aG libvirt $username
arch-chroot /mnt usermod -aG kvm $username

log "Installing GPU drivers"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm mesa lib32-mesa ocl-icd lib32-ocl-icd vulkan-icd-loader lib32-vulkan-icd-loader libva-utils sof-firmware

# # Install Intel packages
# retry arch-chroot /mnt pacman -Syu --needed --noconfirm intel-compute-runtime vulkan-intel lib32-vulkan-intel intel-media-driver vpl-gpu-rt

log "Installing AMDGPU packages"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm vulkan-radeon lib32-vulkan-radeon rocm-opencl-runtime rocm-hip-runtime python-pytorch-opt-rocm

log "Installing PipeWire"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm pipewire pipewire-audio pipewire-pulse pipewire-alsa alsa-utils gst-plugin-pipewire lib32-pipewire wireplumber

# # Install Thermald
# retry arch-chroot /mnt pacman -Syu --needed --noconfirm thermald
# arch-chroot /mnt systemctl enable thermald.service

log "Installing GNOME Desktop Environment"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm baobab eog evince file-roller gdm gnome-calculator gnome-calendar gnome-clocks gnome-color-manager gnome-control-center gnome-font-viewer gnome-keyring gnome-screenshot gnome-shell-extensions gnome-system-monitor gnome-console gnome-themes-extra gnome-video-effects nautilus sushi gnome-tweaks totem xdg-user-dirs-gtk gnome-usage endeavour dconf-editor gnome-shell-extension-appindicator alacarte gnome-text-editor gnome-sound-recorder seahorse gnome-browser-connector xdg-desktop-portal xdg-desktop-portal-gnome gnome-disk-utility libappindicator transmission-gtk power-profiles-daemon gvfs-smb gvfs-google gvfs-mtp gvfs-nfs gnome-logs evolution evolution-ews evolution-on gnome-software gnome-remote-desktop gnome-characters
arch-chroot /mnt systemctl enable gdm.service
arch-chroot /mnt systemctl enable bluetooth.service
run_command_as_user "mkdir -p /home/$username/.config/environment.d"

# # Install KDE Plasma
# retry arch-chroot /mnt pacman -Syu --needed --noconfirm plasma-desktop ark dolphin dolphin-plugins kate konsole kdegraphics-thumbnailers ffmpegthumbs spectacle gwenview bluedevil kinfocenter kscreen plasma-firewall plasma-nm plasma-pa plasma-systemmonitor powerdevil sddm-kcm okular kcalc yakuake cryfs plasma-vault discover breeze-gtk kde-gtk-config gnome-keyring krusader kwalletmanager krename khelpcenter xdg-desktop-portal-kde ktorrent gnome-disk-utility power-profiles-daemon plasma-workspace-wallpapers filelight
# arch-chroot /mnt systemctl enable sddm.service
# arch-chroot /mnt systemctl enable bluetooth.service
# run_command_as_user "mkdir -p /home/$username/.config/environment.d"

log "Granting temporary passwordless sudo for AUR builds"
linum=$(arch-chroot /mnt sed -n "/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL$/=" /etc/sudoers)
arch-chroot /mnt sed -i "${linum}s/^# //" /etc/sudoers

log "Installing Yay AUR helper"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm go git
run_command_as_user "mkdir /home/$username/tmp"
run_command_as_user "git clone https://aur.archlinux.org/yay.git /home/$username/tmp/yay"
run_command_as_user "export GOCACHE='/home/$username/.cache/go-build' && cd /home/$username/tmp/yay && makepkg -sri --noconfirm"

log "Installing fcitx5 and Vietnamese input method"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm fcitx5-bamboo fcitx5-configtool
retry_as_user "yay -Syu --needed --noconfirm gnome-shell-extension-kimpanel-git"
# run_command_as_user "printf 'XMODIFIERS=@im=fcitx\n' > /home/$username/.config/environment.d/fcitx5.conf"

log "Installing fonts"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm ttf-dejavu ttf-liberation noto-fonts-emoji ttf-cascadia-code ttf-fira-code ttf-roboto-mono ttf-hack noto-fonts-cjk

log "Installing web browsers"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm torbrowser-launcher firefox-developer-edition
retry_as_user "yay -Syu --needed --noconfirm google-chrome"

log "Installing general tools"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm keepassxc expect pacman-contrib dosfstools 7zip unarchiver bash-completion flatpak tree archiso rclone rsync lm_sensors exfatprogs pdftk texlive texlive-lang gptfdisk kio5-extras smartmontools ddcutil proton-vpn-gtk-app libreoffice-fresh calibre kolourpaint vlc vlc-plugins-all gst-libav gst-plugins-good gst-plugins-ugly gst-plugins-bad obs-studio inkscape gimp kdenlive frei0r-plugins cdrtools gparted lftp
retry_as_user "yay -Syu --needed --noconfirm ventoy-bin virtio-win"

log "Installing remote desktop tools"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm remmina freerdp

log "Installing programming tools"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm git github-cli git-lfs kdiff3 valgrind kruler emacs-wayland bash-language-server azcopy azure-cli aws-cli-v2 zed jq dbeaver
retry_as_user "yay -Syu --needed --noconfirm visual-studio-code-bin openrefine claude-code storageexplorer databricks-cli-bin sublime-merge"

log "Installing Docker"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm docker docker-compose docker-buildx minikube kubectl helm
arch-chroot /mnt systemctl enable docker.service
arch-chroot /mnt usermod -aG docker $username

log "Installing Java"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm jdk-openjdk openjdk-doc openjdk-src maven gradle gradle-doc

log "Installing Python"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm python uv

log "Installing JavaScript tools"
retry arch-chroot /mnt pacman -Syu --needed --noconfirm nvm eslint prettier
run_command_as_user "printf '\n## nvm configuration\n' >> /home/$username/.bashrc"
run_command_as_user "printf 'source /usr/share/nvm/init-nvm.sh\n' >> /home/$username/.bashrc"

log "Revoking temporary passwordless sudo"
linum=$(arch-chroot /mnt sed -n "/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL$/=" /etc/sudoers)
arch-chroot /mnt sed -i "${linum}s/^/# /" /etc/sudoers

log "Cleaning GnuPG lock files"
run_command_as_user "rm -f /home/$username/.gnupg/public-keys.d/.#lk*"
run_command_as_user "rm -f /home/$username/.gnupg/public-keys/pubring.db.lock"

log "Arch Linux installation completed successfully"
