#!/usr/bin/env bash

set -euo pipefail

source ./system_info.sh

max_attempts=5
attempt=0
until iwctl --passphrase="$wifi_password" station wlan0 connect "$wifi_ssid" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
        echo "Failed to connect to '$wifi_ssid' after $max_attempts attempts."
        exit 1
    fi
    echo "Network '$wifi_ssid' not found, rescanning... (attempt $attempt/$max_attempts)"
    iwctl station wlan0 scan
    sleep 10
done

echo "Connected to '$wifi_ssid' successfully."
sleep 5
if ping -c 3 8.8.8.8 &>/dev/null; then
    echo "Internet connection verified."
else
    echo "Connected to '$wifi_ssid' but no internet access."
    exit 1
fi
