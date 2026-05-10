#!/usr/bin/env bash

set -uo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSIONS_FILE="${SCRIPT_DIR}/vscode-extensions.txt"

# Arrays to track results
FAILED_EXTENSIONS=()
SUCCESS_COUNT=0
FAIL_COUNT=0

# Function to install extension with retry logic
install_extension() {
    local extension=$1
    local max_attempts=3
    local attempt=1
    local wait_time=5

    while [ $attempt -le $max_attempts ]; do
        echo "Installing $extension (attempt $attempt/$max_attempts)..."

        if code --install-extension "$extension" 2>&1; then
            echo -e "${GREEN}✓ Successfully installed $extension${NC}"
            ((SUCCESS_COUNT++))
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                echo -e "${YELLOW}⚠ Failed to install $extension, retrying in ${wait_time}s...${NC}"
                sleep $wait_time
                ((attempt++))
            else
                echo -e "${RED}✗ Failed to install $extension after $max_attempts attempts${NC}"
                FAILED_EXTENSIONS+=("$extension")
                ((FAIL_COUNT++))
                return 1
            fi
        fi
    done
}

if [ ! -f "$EXTENSIONS_FILE" ]; then
    echo -e "${RED}Extensions file not found: $EXTENSIONS_FILE${NC}"
    echo "Generate it with: code --list-extensions > \"$EXTENSIONS_FILE\""
    exit 1
fi

# Read extensions from file (skip blank lines and comments, dedupe)
mapfile -t extensions < <(grep -v '^[[:space:]]*\(#\|$\)' "$EXTENSIONS_FILE" | awk '!seen[$0]++')

if [ ${#extensions[@]} -eq 0 ]; then
    echo -e "${YELLOW}No extensions listed in $EXTENSIONS_FILE${NC}"
    exit 0
fi

echo "Installing ${#extensions[@]} extension(s) from $EXTENSIONS_FILE"
echo ""

for extension in "${extensions[@]}"; do
    install_extension "$extension"
done

# Print summary
echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="
echo -e "${GREEN}Successful: $SUCCESS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"

if [ ${#FAILED_EXTENSIONS[@]} -gt 0 ]; then
    echo ""
    echo "Failed extensions:"
    for ext in "${FAILED_EXTENSIONS[@]}"; do
        echo -e "${RED}  - $ext${NC}"
    done
    echo ""
    echo "You can retry failed extensions manually with:"
    echo "code --install-extension <extension-name>"
fi

echo ""
echo "To refresh the extension list from the current VS Code install, run:"
echo "  code --list-extensions > \"$EXTENSIONS_FILE\""
echo ""
echo "Done!"
