#!/usr/bin/env bash

set -euo pipefail

source ./system_info.sh

iwctl --passphrase="$wifi_password" station wlan0 connect "$wifi_ssid"
sleep 5
ping -c 3 8.8.8.8
