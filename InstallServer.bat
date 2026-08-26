<# :
@echo off
title Installer - Portable Self-Hosted Game Server
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
pause
exit /b
#>

$ErrorActionPreference = "Stop"

Write-Host "=========================================================="
Write-Host "   PORTABLE GAME SERVER INSTALLATION IN WSL"
Write-Host "=========================================================="
Write-Host "This script will download the server to the default WSL environment"
Write-Host "and create a shortcut on your Desktop to start it."
Write-Host "If already installed, it will automatically update the repository."
Write-Host ""

# Check WSL
try {
    $wslStatus = wsl --status 2>&1
} catch {
    Write-Host "[ERROR] WSL does not seem to be installed or an error occurred." -ForegroundColor Red
    Write-Host "Make sure you have WSL2 and Docker Desktop installed before continuing."
    exit 1
}

$RepoUrl = "https://github.com/h4cKEngine/Portable-Self-Hosted-Game-Server-with-Docker.git"
$WslDir = "~/Portable-Self-Hosted-Game-Server-with-Docker"
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$ShortcutName = "StartMcServer.bat"

if (-not (Test-Path $DesktopDir)) {
    $OneDriveDesktop = Join-Path $env:USERPROFILE "OneDrive\Desktop"
    if (Test-Path $OneDriveDesktop) {
        $DesktopDir = $OneDriveDesktop
    }
}
$ShortcutPath = Join-Path $DesktopDir $ShortcutName

Write-Host "[INFO] Preparing environment in WSL path: $WslDir`n"

# Check if dir exists in WSL
$dirExists = (wsl -e bash -c "[ -d $WslDir ] && echo 1 || echo 0").Trim()

if ($dirExists -eq "1") {
    Write-Host "[INFO] The directory $WslDir already exists in WSL."
    Write-Host "[INFO] Updating the project to the latest version (git pull)..."
    wsl -e bash -c "cd $WslDir && git config core.fileMode false && git pull"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to update the repository. Please resolve the git errors above." -ForegroundColor Red
        exit 1
    }

    Write-Host "[INFO] Setting permissions on scripts..."
    wsl -e bash -c "cd $WslDir && chmod +x *.sh utils/*.sh 2>/dev/null || true"

    if (Test-Path $ShortcutPath) {
        Write-Host "=========================================================="
        Write-Host "[INFO] Repository updated successfully." -ForegroundColor Green
        Write-Host "[INFO] You can start the server using the Desktop shortcut!" -ForegroundColor Green
        Write-Host "=========================================================="
        Write-Host ""
        exit 0
    }
} else {
    Write-Host "[INFO] Cloning the project from GitHub..."
    wsl -e bash -c "git clone $RepoUrl $WslDir"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to download the repository. Please check your internet connection." -ForegroundColor Red
        exit 1
    }
    Write-Host "[INFO] Setting permissions on scripts..."
    wsl -e bash -c "cd $WslDir && git config core.fileMode false && chmod +x *.sh utils/*.sh 2>/dev/null || true"
}

Write-Host "`n[INFO] Creating quick start shortcut on Windows Desktop..."

$LauncherScript = @"
@echo off
title Game Server Dashboard
echo ==========================================================
echo       STARTING GAME SERVER DASHBOARD (WSL Bridge)
echo ==========================================================
echo Project Path: $WslDir
echo Starting web container and host agent...
wsl -e bash -c "cd $WslDir && chmod +x *.sh utils/*.sh && ./utils/setup-web.sh && { explorer.exe http://localhost/index.html || true; } && ./utils/host-agent.sh"
echo Dashboard closed.
pause
"@

$LauncherScript | Out-File -FilePath $ShortcutPath -Encoding ascii

Write-Host "`n=========================================================="
Write-Host "   INSTALLATION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "=========================================================="
Write-Host "You will find a '$ShortcutName' file on your Desktop."
Write-Host "Double click that file whenever you want to "
Write-Host "start the server and the web dashboard."
Write-Host ""
