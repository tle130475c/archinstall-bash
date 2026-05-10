#Requires -Version 5.1

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExtensionsFile = Join-Path $ScriptDir 'vscode-extensions.txt'

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

if (-not (Test-Path -LiteralPath $ExtensionsFile)) {
    Write-Host "Extensions file not found: $ExtensionsFile" -ForegroundColor Red
    Write-Host "Generate it with: code --list-extensions > `"$ExtensionsFile`""
    exit 1
}

# Read extensions from file (skip blank lines and comments, dedupe, preserve order)
$Extensions = Get-Content -LiteralPath $ExtensionsFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    Select-Object -Unique

if (-not $Extensions -or $Extensions.Count -eq 0) {
    Write-Host "No extensions listed in $ExtensionsFile" -ForegroundColor Yellow
    exit 0
}

Write-Host "Installing $($Extensions.Count) extension(s) from $ExtensionsFile"
Write-Host ""

foreach ($extension in $Extensions) {
    Install-VscodeExtension $extension
}

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
Write-Host "To refresh the extension list from the current VS Code install, run:"
Write-Host "  code --list-extensions > `"$ExtensionsFile`""
Write-Host ""
Write-Host "Done!"
