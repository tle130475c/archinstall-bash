#!/usr/bin/env bash
#
# verify_installed_packages.sh — Verify that all packages from an Arch install
#                                script are actually installed in the target system.
#
# Usage: ./verify_installed_packages.sh [script_file] [root]
#        script_file  defaults to ./install_archlinux.sh
#        root         defaults to / (use /mnt to check a chroot installation)

set -uo pipefail

SCRIPT_FILE="${1:-./install_archlinux.sh}"
ROOT="${2:-/}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

if [[ ! -f "$SCRIPT_FILE" ]]; then
    printf "${RED}Error: '%s' not found.${NC}\n" "$SCRIPT_FILE" >&2
    exit 1
fi

if [[ ! -d "$ROOT" ]]; then
    printf "${RED}Error: root directory '%s' not found.${NC}\n" "$ROOT" >&2
    exit 1
fi

printf "${BOLD}Verifying installed packages from: %s${NC}\n" "$SCRIPT_FILE"
printf "${BOLD}Target root: %s${NC}\n\n" "$ROOT"

# ── Package extraction ────────────────────────────────────────────────────────
# Same parsing logic as check_packages.sh; covers pacstrap, pacman -S, yay -S.
# Packages are deduplicated via sort -u.
mapfile -t packages < <(awk '
    /^[[:space:]]*#/ { next }

    /pacstrap/ {
        skip = 0; active = 0
        for (i = 1; i <= NF; i++) {
            tok = $i; gsub(/"|'"'"'/, "", tok)
            if (tok == "pacstrap")    { active = 1; skip = 1; continue }
            if (active && skip)       { skip = 0;              continue }
            if (active && tok ~ /^-/) continue
            if (active && tok != "")  print tok
        }
    }

    /pacman[[:space:]]+-S/ {
        active = 0
        for (i = 1; i <= NF; i++) {
            tok = $i; gsub(/"|'"'"'/, "", tok)
            if (tok == "pacman")      { active = 1; continue }
            if (active && tok ~ /^-/) continue
            if (active && tok != "")  print tok
        }
    }

    /yay[[:space:]]+-S/ {
        active = 0
        for (i = 1; i <= NF; i++) {
            tok = $i; gsub(/"|'"'"'/, "", tok)
            if (tok == "yay")         { active = 1; continue }
            if (active && tok ~ /^-/) continue
            if (active && tok != "")  print tok
        }
    }
' "$SCRIPT_FILE" | sort -u)

printf "Found ${BOLD}%d${NC} unique packages to verify\n\n" "${#packages[@]}"

# ── Helpers ───────────────────────────────────────────────────────────────────
pacman_cmd() {
    if [[ "$ROOT" == "/" ]]; then
        pacman "$@" 2>/dev/null
    else
        pacman -r "$ROOT" "$@" 2>/dev/null
    fi
}

pkg_query() {
    # Returns "name version" if installed, empty string otherwise.
    pacman_cmd -Q "$1"
}

group_members() {
    # Returns member package names for a group, empty if not a group.
    pacman_cmd -Sg "$1" | awk '{print $2}'
}

# ── Verify each package ───────────────────────────────────────────────────────
ok=0
fail=0
declare -a missing=()

printf "${BOLD}${BLUE}=== Installation Status ===${NC}\n"

for pkg in "${packages[@]}"; do
    printf "  %-55s" "$pkg"
    result=$(pkg_query "$pkg")
    if [[ -n "$result" ]]; then
        version=$(awk '{print $2}' <<< "$result")
        printf "${GREEN}[  OK  ]${NC}  (%s)\n" "$version"
        ((ok++)) || true
    else
        # Not a regular package — check if it's a group
        mapfile -t members < <(group_members "$pkg")
        if [[ ${#members[@]} -gt 0 ]]; then
            installed=0
            for m in "${members[@]}"; do
                [[ -n "$(pkg_query "$m")" ]] && ((installed++)) || true
            done
            total=${#members[@]}
            if ((installed == total)); then
                printf "${GREEN}[GROUP %d/%d]${NC}\n" "$installed" "$total"
                ((ok++)) || true
            elif ((installed > 0)); then
                printf "${YELLOW}[GROUP %d/%d]${NC}  (partial)\n" "$installed" "$total"
                ((fail++)) || true
                missing+=("$pkg (group $installed/$total)")
            else
                printf "${RED}[MISSING]${NC}  (group 0/%d)\n" "$total"
                ((fail++)) || true
                missing+=("$pkg")
            fi
        else
            printf "${RED}[MISSING]${NC}\n"
            ((fail++)) || true
            missing+=("$pkg")
        fi
    fi
done

printf "\n"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "${BOLD}=== Summary ===${NC}\n"
printf "  ${GREEN}%d installed${NC}  /  ${RED}%d missing${NC}   (total %d)\n" \
    "$ok" "$fail" "$((ok + fail))"

if [[ ${#missing[@]} -gt 0 ]]; then
    printf "\n${BOLD}${RED}=== Missing Packages ===${NC}\n"
    for p in "${missing[@]}"; do
        printf "  ${RED}✗${NC}  %s\n" "$p"
    done
    printf "\n"
    exit 1
else
    printf "\n${GREEN}${BOLD}All packages are installed!${NC}\n\n"
fi
