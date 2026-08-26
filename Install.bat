<# :
@echo off
title Installer - Portable Self-Hosted Game Server
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
pause
exit /b
#>

$ErrorActionPreference = "Stop"

Write-Host "=========================================================="
Write-Host "   INSTALLAZIONE GAME SERVER PORTABLE IN WSL"
Write-Host "=========================================================="
Write-Host "Questo script scarichera' il server nell'ambiente WSL di default"
Write-Host "e creera' un collegamento sul Desktop per avviarlo."
Write-Host ""

# Check WSL
try {
    $wslStatus = wsl --status 2>&1
} catch {
    Write-Host "[ERRORE] WSL non sembra essere installato o si e' verificato un errore." -ForegroundColor Red
    Write-Host "Assicurati di avere WSL2 e Docker Desktop installati prima di continuare."
    exit 1
}

$RepoUrl = "https://github.com/h4cKEngine/Portable-Self-Hosted-Game-Server-with-Docker.git"
$WslDir = "~/Portable-Self-Hosted-Game-Server-with-Docker"
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$ShortcutName = "Avvia Game Server.bat"

if (-not (Test-Path $DesktopDir)) {
    $OneDriveDesktop = Join-Path $env:USERPROFILE "OneDrive\Desktop"
    if (Test-Path $OneDriveDesktop) {
        $DesktopDir = $OneDriveDesktop
    }
}
$ShortcutPath = Join-Path $DesktopDir $ShortcutName

Write-Host "[INFO] Preparazione ambiente nel percorso WSL: $WslDir`n"

# Check if dir exists in WSL
$dirExists = (wsl -e bash -c "[ -d $WslDir ] && echo 1 || echo 0").Trim()

if ($dirExists -eq "1") {
    if (Test-Path $ShortcutPath) {
        Write-Host "=========================================================="
        Write-Host "[INFO] Repo gia' scaricata e installata in precedenza." -ForegroundColor Green
        Write-Host "[INFO] Puoi avviare il server usando l'icona sul Desktop!" -ForegroundColor Green
        Write-Host "=========================================================="
        Write-Host ""
        exit 0
    }
    
    Write-Host "[INFO] La cartella $WslDir esiste gia' in WSL."
    Write-Host "[INFO] Aggiornamento del progetto all'ultima versione (git pull)..."
    wsl -e bash -c "cd $WslDir && git pull"
} else {
    Write-Host "[INFO] Clonazione del progetto da GitHub in corso..."
    wsl -e bash -c "git clone $RepoUrl $WslDir"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERRORE] Impossibile scaricare la repository. Verifica la tua connessione a Internet." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n[INFO] Creazione del file di avvio rapido sul Desktop di Windows..."

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
Write-Host "   INSTALLAZIONE COMPLETATA CON SUCCESSO!" -ForegroundColor Green
Write-Host "=========================================================="
Write-Host "Troverai un file '$ShortcutName' sul tuo Desktop."
Write-Host "Fai doppio clic su quel file ogni volta che vorrai "
Write-Host "avviare il server e la web dashboard."
Write-Host ""
