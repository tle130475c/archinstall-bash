#!/usr/bin/env bash

set -uo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Install extensions
install_extension angular.ng-template
install_extension bdavs.expect
install_extension bmewburn.vscode-intelephense-client
install_extension celianriboulet.webvalidator
install_extension charliermarsh.ruff
install_extension christian-kohler.npm-intellisense
install_extension christian-kohler.path-intellisense
install_extension codezombiech.gitignore
install_extension cschlosser.doxdocgen
install_extension davidanson.vscode-markdownlint
install_extension dbaeumer.vscode-eslint
install_extension docker.docker
install_extension eamodio.gitlens
install_extension editorconfig.editorconfig
install_extension esbenp.prettier-vscode
install_extension foxundermoon.shell-format
install_extension github.copilot
install_extension github.copilot-chat
install_extension github.remotehub
install_extension github.vscode-pull-request-github
install_extension gruntfuggly.todo-tree
install_extension humao.rest-client
install_extension janisdd.vscode-edit-csv
install_extension jbockle.jbockle-format-files
install_extension johnpapa.vscode-peacock
install_extension mads-hartmann.bash-ide-vscode
install_extension mechatroner.rainbow-csv
install_extension ms-azuretools.vscode-azureresourcegroups
install_extension ms-azuretools.vscode-containers
install_extension ms-azuretools.vscode-docker
install_extension ms-dotnettools.csdevkit
install_extension ms-edgedevtools.vscode-edge-devtools
install_extension ms-kubernetes-tools.vscode-kubernetes-tools
install_extension ms-python.debugpy
install_extension ms-python.python
install_extension ms-python.vscode-pylance
install_extension ms-python.vscode-python-envs
install_extension ms-toolsai.jupyter
install_extension ms-vscode-remote.vscode-remote-extensionpack
install_extension ms-vscode.cpptools-extension-pack
install_extension ms-vscode.live-server
install_extension ms-vscode.vscode-node-azure-pack
install_extension msjsdiag.vscode-react-native
install_extension neo4j-extensions.neo4j-for-vscode
install_extension oderwat.indent-rainbow
install_extension okteto.remote-kubernetes
install_extension redhat.vscode-apache-camel
install_extension redhat.vscode-community-server-connector
install_extension redhat.vscode-quarkus
install_extension redhat.vscode-xml
install_extension redhat.vscode-yaml
install_extension rogalmic.bash-debug
install_extension rust-lang.rust-analyzer
install_extension sonarsource.sonarlint-vscode
install_extension streetsidesoftware.code-spell-checker
install_extension tomoki1207.pdf
install_extension tomwhite007.rename-angular-component
install_extension vmware.vscode-boot-dev-pack
install_extension vscjava.vscode-java-pack
install_extension wayou.vscode-todo-highlight
install_extension wmaurer.change-case
install_extension yy0931.save-as-root
install_extension yzane.markdown-pdf
install_extension ztt25.azure-devops-boards-vscode
install_extension anthropic.claude-code
install_extension pkief.material-icon-theme

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
echo "Done!"
