#Requires -Version 5.1

# Arrays to track results
$FailedExtensions = @()
$SuccessCount = 0
$FailCount = 0

function Install-VscodeExtension {
    param(
        [string]$Extension,
        [int]$MaxAttempts = 3,
        [int]$WaitSeconds = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host "Installing $Extension (attempt $attempt/$MaxAttempts)..."

        code --install-extension $Extension 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Successfully installed $Extension" -ForegroundColor Green
            $script:SuccessCount++
            return
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Host "[WARN] Failed to install $Extension, retrying in ${WaitSeconds}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $WaitSeconds
        } else {
            Write-Host "[FAIL] Failed to install $Extension after $MaxAttempts attempts" -ForegroundColor Red
            $script:FailedExtensions += $Extension
            $script:FailCount++
        }
    }
}

# Install extensions
Install-VscodeExtension angular.ng-template
Install-VscodeExtension anthropic.claude-code
Install-VscodeExtension bdavs.expect
Install-VscodeExtension bmewburn.vscode-intelephense-client
Install-VscodeExtension bradlc.vscode-tailwindcss
Install-VscodeExtension celianriboulet.webvalidator
Install-VscodeExtension charliermarsh.ruff
Install-VscodeExtension christian-kohler.npm-intellisense
Install-VscodeExtension christian-kohler.path-intellisense
Install-VscodeExtension codezombiech.gitignore
Install-VscodeExtension cschlosser.doxdocgen
Install-VscodeExtension davidanson.vscode-markdownlint
Install-VscodeExtension dbaeumer.vscode-eslint
Install-VscodeExtension docker.docker
Install-VscodeExtension eamodio.gitlens
Install-VscodeExtension editorconfig.editorconfig
Install-VscodeExtension esbenp.prettier-vscode
Install-VscodeExtension foxundermoon.shell-format
Install-VscodeExtension github.copilot
Install-VscodeExtension github.copilot-chat
Install-VscodeExtension github.remotehub
Install-VscodeExtension github.vscode-pull-request-github
Install-VscodeExtension gruntfuggly.todo-tree
Install-VscodeExtension humao.rest-client
Install-VscodeExtension janisdd.vscode-edit-csv
Install-VscodeExtension jbockle.jbockle-format-files
Install-VscodeExtension johnpapa.vscode-peacock
Install-VscodeExtension mads-hartmann.bash-ide-vscode
Install-VscodeExtension mechatroner.rainbow-csv
Install-VscodeExtension ms-azuretools.vscode-azureresourcegroups
Install-VscodeExtension ms-azuretools.vscode-containers
Install-VscodeExtension ms-azuretools.vscode-docker
Install-VscodeExtension ms-dotnettools.csdevkit
Install-VscodeExtension ms-edgedevtools.vscode-edge-devtools
Install-VscodeExtension ms-kubernetes-tools.vscode-kubernetes-tools
Install-VscodeExtension ms-python.debugpy
Install-VscodeExtension ms-python.python
Install-VscodeExtension ms-python.vscode-pylance
Install-VscodeExtension ms-python.vscode-python-envs
Install-VscodeExtension ms-toolsai.jupyter
Install-VscodeExtension ms-vscode-remote.vscode-remote-extensionpack
Install-VscodeExtension ms-vscode.cpptools-extension-pack
Install-VscodeExtension ms-vscode.live-server
Install-VscodeExtension ms-vscode.vscode-node-azure-pack
Install-VscodeExtension msjsdiag.vscode-react-native
Install-VscodeExtension neo4j-extensions.neo4j-for-vscode
Install-VscodeExtension oderwat.indent-rainbow
Install-VscodeExtension okteto.remote-kubernetes
Install-VscodeExtension redhat.vscode-apache-camel
Install-VscodeExtension redhat.vscode-community-server-connector
Install-VscodeExtension redhat.vscode-quarkus
Install-VscodeExtension redhat.vscode-xml
Install-VscodeExtension redhat.vscode-yaml
Install-VscodeExtension rogalmic.bash-debug
Install-VscodeExtension rust-lang.rust-analyzer
Install-VscodeExtension sonarsource.sonarlint-vscode
Install-VscodeExtension streetsidesoftware.code-spell-checker
Install-VscodeExtension tomoki1207.pdf
Install-VscodeExtension tomwhite007.rename-angular-component
Install-VscodeExtension usernamehw.errorlens
Install-VscodeExtension vmware.vscode-boot-dev-pack
Install-VscodeExtension vscjava.vscode-java-pack
Install-VscodeExtension wayou.vscode-todo-highlight
Install-VscodeExtension wmaurer.change-case
Install-VscodeExtension yy0931.save-as-root
Install-VscodeExtension yzane.markdown-pdf
Install-VscodeExtension ztt25.azure-devops-boards-vscode
Install-VscodeExtension anthropic.claude-code
Install-VscodeExtension pkief.material-icon-theme

# Print summary
Write-Host ""
Write-Host "=========================================="
Write-Host "Installation Summary"
Write-Host "=========================================="
Write-Host "Successful: $SuccessCount" -ForegroundColor Green
Write-Host "Failed: $FailCount" -ForegroundColor Red

if ($FailedExtensions.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed extensions:"
    foreach ($ext in $FailedExtensions) {
        Write-Host "  - $ext" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "You can retry failed extensions manually with:"
    Write-Host "code --install-extension <extension-name>"
}

Write-Host ""
Write-Host "Done!"
