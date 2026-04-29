# Install pre-commit hooks for this repository
# Run this script once to set up the validation system

$ErrorActionPreference = "Stop"
$projectRoot = git rev-parse --show-toplevel
$hooksSource = "$projectRoot/scripts/git-hooks"
$hooksTarget = "$projectRoot/.git/hooks"

Write-Host "Installing pre-commit hooks..." -ForegroundColor Cyan

# Copy hook files
Write-Host ""
Write-Host "Copying hook files..." -ForegroundColor Yellow
try {
    Copy-Item "$hooksSource/pre-commit.ps1" "$hooksTarget/pre-commit.ps1" -Force
    Copy-Item "$hooksSource/pre-commit" "$hooksTarget/pre-commit" -Force
    Write-Host "[OK] Hook files copied" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Could not copy hook files: $_" -ForegroundColor Red
    exit 1
}

# Make hooks executable
Write-Host ""
Write-Host "Setting permissions..." -ForegroundColor Yellow
try {
    $username = $env:USERNAME
    icacls "$hooksTarget/pre-commit" /grant:r "$($username):F" | Out-Null
    icacls "$hooksTarget/pre-commit.ps1" /grant:r "$($username):F" | Out-Null
    Write-Host "[OK] Permissions set" -ForegroundColor Green
} catch {
    Write-Host "[WARN] Could not set permissions (may still work)" -ForegroundColor Yellow
}

# Configure git to use hooks directory
Write-Host ""
Write-Host "Configuring Git..." -ForegroundColor Yellow
try {
    git config core.hooksPath .git/hooks
    Write-Host "[OK] Git configured to use hooks" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Could not configure Git: $_" -ForegroundColor Red
    exit 1
}

# Test the hook
Write-Host ""
Write-Host "Testing hook..." -ForegroundColor Yellow
& $hooksTarget/pre-commit.ps1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[SUCCESS] Pre-commit hooks installed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your project now validates before each commit:" -ForegroundColor Cyan
    Write-Host "  - Godot script syntax checks" -ForegroundColor Cyan
    Write-Host "  - Debug options verification" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Bypass with: git commit --no-verify" -ForegroundColor Blue
} else {
    Write-Host ""
    Write-Host "[WARN] Installation complete but validation test failed" -ForegroundColor Yellow
    exit 1
}
