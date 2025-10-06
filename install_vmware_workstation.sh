#!/usr/bin/env bash

set -euo pipefail

# VMware Workstation
run_command_as_user "yay -Syu --needed --noconfirm vmware-keymaps"
run_command_as_user "yay -Syu --needed --noconfirm vmware-workstation"
arch-chroot /mnt systemctl enable vmware-networks.service
arch-chroot /mnt systemctl enable vmware-usbarbitrator.service