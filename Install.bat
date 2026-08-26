@echo off
setlocal EnableDelayedExpansion
title Installer - Portable Self-Hosted Game Server

echo ==========================================================
echo    INSTALLAZIONE GAME SERVER PORTABLE IN WSL
echo ==========================================================
echo Questo script scarichera' il server nell'ambiente WSL di default
echo e creera' un collegamento sul Desktop per avviarlo.
echo.

:: Verifica se WSL e' disponibile
wsl --status >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRORE] WSL non sembra essere installato, oppure il comando ha fallito.
    echo Assicurati di avere WSL2 e Docker Desktop installati prima di continuare.
    pause
    exit /b 1
)

set REPO_URL=https://github.com/h4cKEngine/Portable-Self-Hosted-Game-Server-with-Docker.git
set WSL_DIR=~/Portable-Self-Hosted-Game-Server-with-Docker
set DESKTOP_DIR=%USERPROFILE%\Desktop
set SHORTCUT_NAME=Avvia Game Server.bat

echo [INFO] Preparazione ambiente nel percorso WSL: %WSL_DIR%
echo.

:: Controlla se la cartella esiste gia' in WSL
wsl -e bash -c "[ -d %WSL_DIR% ]"
if %errorlevel% equ 0 (
    echo [INFO] La cartella %WSL_DIR% esiste gia' in WSL.
    echo [INFO] Aggiornamento del progetto all'ultima versione (git pull)...
    wsl -e bash -c "cd %WSL_DIR% && git pull"
) else (
    echo [INFO] Clonazione del progetto da GitHub in corso...
    wsl -e bash -c "git clone %REPO_URL% %WSL_DIR%"
    if !errorlevel! neq 0 (
        echo [ERRORE] Impossibile scaricare la repository. Verifica la tua connessione a Internet.
        pause
        exit /b 1
    )
)

:: Creazione dello script launcher sul Desktop
echo.
echo [INFO] Creazione del file di avvio rapido sul Desktop di Windows...
(
echo @echo off
echo title Game Server Dashboard
echo echo ==========================================================
echo echo       STARTING GAME SERVER DASHBOARD ^(WSL Bridge^)
echo echo ==========================================================
echo echo Project Path: %WSL_DIR%
echo echo Starting web container and host agent...
echo wsl -e bash -c "cd %WSL_DIR% && chmod +x *.sh utils/*.sh && ./utils/setup-web.sh && (explorer.exe http://localhost/index.html || true) && ./utils/host-agent.sh"
echo echo Dashboard closed.
echo pause
) > "%DESKTOP_DIR%\%SHORTCUT_NAME%"

echo.
echo ==========================================================
echo    INSTALLAZIONE COMPLETATA CON SUCCESSO!
echo ==========================================================
echo Troverai un file "%SHORTCUT_NAME%" sul tuo Desktop.
echo Fai doppio clic su quel file ogni volta che vorrai 
echo avviare il server e la web dashboard.
echo.
pause
