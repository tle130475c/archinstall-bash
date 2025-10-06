#!/usr/bin/env bash

set -euo pipefail

source ./system_info.sh

sgdisk -Z /dev/$disk_name
wipefs -a /dev/$disk_name
