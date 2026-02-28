#!/usr/bin/env bash

set -euo pipefail

yay -Syu --needed --noconfirm vmware-keymaps
yay -Syu --needed --noconfirm vmware-workstation
sudo systemctl start vmware-networks-configuration.service
sudo systemctl enable --now vmware-networks.service
sudo systemctl enable --now vmware-usbarbitrator.service
