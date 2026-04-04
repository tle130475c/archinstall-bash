#!/usr/bin/env bash

set -euo pipefail

gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com

gsettings set org.gnome.desktop.interface font-antialiasing rgba
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.interface clock-format 24h
gsettings set org.gnome.nautilus.preferences default-folder-viewer list-view
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type nothing
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.desktop.session idle-delay "uint32 0"

# Custom keyboard shortcuts
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
"$SCRIPT_DIR/create_gnome_shortcut.sh" add "Terminal" "<Control><Alt>t" "kgx"
"$SCRIPT_DIR/create_gnome_shortcut.sh" add "Google Chrome" "<Control><Alt>c" "google-chrome-stable"
"$SCRIPT_DIR/create_gnome_shortcut.sh" add "File Manager" "<Super>e" "nautilus"
"$SCRIPT_DIR/create_gnome_shortcut.sh" add "KeePassXC" "<Control><Alt>p" "keepassxc"
