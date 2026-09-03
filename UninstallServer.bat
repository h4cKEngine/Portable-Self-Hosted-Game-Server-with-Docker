<# :
@echo off
title Uninstaller - Portable Self-Hosted Game Server
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ScriptFile='%~f0'; Invoke-Expression (Get-Content '%~f0' -Raw)"
pause
exit /b
#>

$ErrorActionPreference = "Stop"

Write-Host "=========================================================="
Write-Host "   PORTABLE GAME SERVER UNINSTALLATION"
Write-Host "=========================================================="
Write-Host "WARNING: This will completely remove the server, all its data,"
Write-Host "containers, and desktop shortcuts."
Write-Host "This action CANNOT BE UNDONE!"
Write-Host "=========================================================="
Write-Host ""

$confirmation = Read-Host "Are you absolutely sure you want to proceed? Type 'YES' to confirm"
if ($confirmation -cne "YES") {
    Write-Host "`n[INFO] Uninstallation aborted." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[INFO] Proceeding with uninstallation..." -ForegroundColor Cyan

# Variables
$WslDir = "~/Portable-Self-Hosted-Game-Server-with-Docker"
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$OneDriveDesktop = Join-Path $env:USERPROFILE "OneDrive\Desktop"

if (-not (Test-Path $DesktopDir)) {
    if (Test-Path $OneDriveDesktop) {
        $DesktopDir = $OneDriveDesktop
    }
}

$StartShortcutName = "StartMcServer.lnk"
$StartShortcutPath = Join-Path $DesktopDir $StartShortcutName
$InstallShortcutName = "InstallServer.lnk"
$InstallShortcutPath = Join-Path $DesktopDir $InstallShortcutName
$AppDataDir = Join-Path $env:LOCALAPPDATA "PortableMcServer"

# Check WSL
try {
    $wslStatus = wsl --status 2>&1
} catch {
    Write-Host "[ERROR] WSL does not seem to be installed or an error occurred." -ForegroundColor Red
    exit 1
}

$dirExists = (wsl -e bash -c "[ -d $WslDir ] && echo 1 || echo 0").Trim()

if ($dirExists -eq "1") {
    Write-Host "[INFO] Stopping any running Docker containers..."
    wsl -e bash -c "cd $WslDir && docker compose down -v 2>/dev/null || true"
    wsl -e bash -c "cd $WslDir && docker compose -p mc-dashboard -f docker-compose.dashboard.yml down -v 2>/dev/null || true"
    
    Write-Host "[INFO] Removing project directory from WSL..."
    $WslFullPath = (wsl -e bash -c "echo $WslDir" 2>$null).Trim()
    if ($WslFullPath) {
        wsl -u root -e bash -c "rm -rf $WslFullPath"
    } else {
        wsl -e bash -c "sudo rm -rf $WslDir"
    }

    $dirStillExists = (wsl -e bash -c "[ -d $WslDir ] && echo 1 || echo 0").Trim()
    if ($dirStillExists -eq "0") {
        Write-Host "  -> WSL project directory removed." -ForegroundColor Green
    } else {
        Write-Host "  -> Failed to completely remove WSL project directory." -ForegroundColor Red
    }
} else {
    Write-Host "[INFO] Project directory not found in WSL. Skipping removal."
}

Write-Host "[INFO] Removing Desktop Shortcuts..."
if (Test-Path $StartShortcutPath) {
    Remove-Item -Path $StartShortcutPath -Force -ErrorAction SilentlyContinue
    Write-Host "  -> Removed $StartShortcutName" -ForegroundColor Green
}
if (Test-Path $InstallShortcutPath) {
    Remove-Item -Path $InstallShortcutPath -Force -ErrorAction SilentlyContinue
    Write-Host "  -> Removed $InstallShortcutName" -ForegroundColor Green
}

Write-Host "[INFO] Removing AppData directory..."
if (Test-Path $AppDataDir) {
    Remove-Item -Path $AppDataDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  -> Removed $AppDataDir" -ForegroundColor Green
}

Write-Host "`n=========================================================="
Write-Host "   UNINSTALLATION COMPLETE"
Write-Host "=========================================================="
Write-Host "The Portable Self-Hosted Game Server has been removed from"
Write-Host "your system."
Write-Host "=========================================================="
