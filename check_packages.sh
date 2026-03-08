#!/usr/bin/env bash
#
# check_packages.sh — Validate that all packages in an Arch install script
#                     are available in official repos or the AUR.
#
# Usage: ./check_packages.sh [script_file]
#        Defaults to ./install_archlinux.sh

set -uo pipefail

SCRIPT_FILE="${1:-./install_archlinux.sh}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

if [[ ! -f "$SCRIPT_FILE" ]]; then
    echo -e "${RED}Error: '$SCRIPT_FILE' not found.${NC}" >&2
    exit 1
fi

echo -e "${BOLD}Extracting packages from: $SCRIPT_FILE${NC}\n"

# ── Package extraction ───────────────────────────────────────────────────────
# Outputs lines of the form:  pacman:<linenum>:<pkg>  or  aur:<linenum>:<pkg>
# Handles:
#   pacstrap /mnt pkg1 pkg2 ...
#   [arch-chroot /mnt] pacman -Syu --needed --noconfirm pkg1 pkg2 ...
#   [run_command_as_user "] yay -Syu --needed --noconfirm pkg1 pkg2 ["]
# Skips lines that are fully commented out.
mapfile -t raw_entries < <(awk '
    /^[[:space:]]*#/ { next }

    /pacstrap/ {
        skip = 0; active = 0
        for (i = 1; i <= NF; i++) {
            tok = $i; gsub(/"|\047/, "", tok)
            if (tok == "pacstrap")         { active = 1; skip = 1; continue }
            if (active && skip)            { skip = 0; continue }   # skip /mnt
            if (active && tok ~ /^-/)      continue                 # skip flags
            if (active && tok != "")       print "pacman:" NR ":" tok
        }
    }

    /pacman[[:space:]]+-S/ {
        active = 0
        for (i = 1; i <= NF; i++) {
            tok = $i; gsub(/"|\047/, "", tok)
            if (tok == "pacman")           { active = 1; continue }
            if (active && tok ~ /^-/)      continue
            if (active && tok != "")       print "pacman:" NR ":" tok
        }
    }

    /yay[[:space:]]+-S/ {
        active = 0
        for (i = 1; i <= NF; i++) {
            tok = $i; gsub(/"|\047/, "", tok)
            if (tok == "yay")              { active = 1; continue }
            if (active && tok ~ /^-/)      continue
            if (active && tok != "")       print "aur:" NR ":" tok
        }
    }
' "$SCRIPT_FILE")

declare -a pacman_entries=() aur_entries=()
for entry in "${raw_entries[@]}"; do
    [[ "$entry" == pacman:* ]] && pacman_entries+=("$entry")
    [[ "$entry" == aur:* ]]    && aur_entries+=("$entry")
done

echo -e "Found ${BOLD}${#pacman_entries[@]}${NC} official packages, ${BOLD}${#aur_entries[@]}${NC} AUR packages\n"

# ── Check official packages ──────────────────────────────────────────────────
pacman_ok=0
pacman_fail=0
declare -a pacman_missing=()

echo -e "${BOLD}${BLUE}=== Official Repository Packages ===${NC}"

# Warn if sync DBs might be stale
if ! pacman -Si pacman &>/dev/null 2>&1; then
    echo -e "${YELLOW}  Warning: pacman sync DB may be empty — run 'sudo pacman -Sy' for accurate results.${NC}\n"
fi

for entry in "${pacman_entries[@]}"; do
    IFS=':' read -r _ linenum pkg <<< "$entry"
    printf "  %-55s" "$pkg"
    if pacman -Si "$pkg" &>/dev/null 2>&1; then
        echo -e "${GREEN}[  OK  ]${NC}"
        ((pacman_ok++)) || true
    else
        echo -e "${RED}[MISSING]${NC}  (line $linenum)"
        ((pacman_fail++)) || true
        pacman_missing+=("$pkg (line $linenum)")
    fi
done

echo ""

# ── Check AUR packages ───────────────────────────────────────────────────────
aur_ok=0
aur_fail=0
declare -a aur_missing=()

echo -e "${BOLD}${BLUE}=== AUR Packages ===${NC}"

check_aur() {
    local pkg="$1"
    # Prefer yay if available on the host
    if command -v yay &>/dev/null; then
        yay -Si "$pkg" &>/dev/null 2>&1
        return
    fi
    # Fallback: AUR RPC v5 (requires curl + internet)
    if ! command -v curl &>/dev/null; then
        echo -e "${YELLOW}  Warning: neither yay nor curl found — cannot check AUR packages.${NC}" >&2
        return 1
    fi
    local count
    count=$(curl -sf "https://aur.archlinux.org/rpc/v5/info?arg[]=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$pkg" 2>/dev/null || echo "$pkg")" \
        | grep -o '"resultcount":[0-9]*' | grep -o '[0-9]*')
    [[ "${count:-0}" -gt 0 ]]
}

for entry in "${aur_entries[@]}"; do
    IFS=':' read -r _ linenum pkg <<< "$entry"
    printf "  %-55s" "$pkg"
    if check_aur "$pkg"; then
        echo -e "${GREEN}[  OK  ]${NC}"
        ((aur_ok++)) || true
    else
        echo -e "${RED}[MISSING]${NC}  (line $linenum)"
        ((aur_fail++)) || true
        aur_missing+=("$pkg (line $linenum)")
    fi
done

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}=== Summary ===${NC}"
echo -e "  Official  :  ${GREEN}${pacman_ok} OK${NC}  /  ${RED}${pacman_fail} missing${NC}   (total $((pacman_ok + pacman_fail)))"
echo -e "  AUR       :  ${GREEN}${aur_ok} OK${NC}  /  ${RED}${aur_fail} missing${NC}   (total $((aur_ok + aur_fail)))"

if [[ ${#pacman_missing[@]} -gt 0 || ${#aur_missing[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}${RED}=== Missing Packages ===${NC}"
    if [[ ${#pacman_missing[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}Official Repos:${NC}"
        for p in "${pacman_missing[@]}"; do
            echo -e "    ${RED}✗${NC}  $p"
        done
    fi
    if [[ ${#aur_missing[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}AUR:${NC}"
        for p in "${aur_missing[@]}"; do
            echo -e "    ${RED}✗${NC}  $p"
        done
    fi
    echo ""
    exit 1
else
    echo ""
    echo -e "${GREEN}${BOLD}All packages are available!${NC}\n"
fi
