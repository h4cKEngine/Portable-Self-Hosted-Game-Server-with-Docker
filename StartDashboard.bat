@echo off
setlocal EnableDelayedExpansion

:: Abilita il supporto per i percorsi di rete (UNC)
pushd "%~dp0"

set CURRENT_DIR=%~dp0
if "%CURRENT_DIR:~-1%"=="\" set CURRENT_DIR=%CURRENT_DIR:~0,-1%
set DEFAULT_WSL_DIR=~/Portable-Self-Hosted-Game-Server-with-Docker

echo ==========================================================
echo       STARTING GAME SERVER DASHBOARD (WSL Bridge)
echo ==========================================================

:: Verifica se ci troviamo in un disco Windows (es. C:\, D:\)
echo %CURRENT_DIR% | findstr /i "^[A-Z]:" >nul
if %errorlevel% equ 0 (
    echo [INFO] Esecuzione da filesystem Windows rilevata.
    
    :: Controlla se il server e' gia' stato copiato in WSL
    wsl -e bash -c "[ -d %DEFAULT_WSL_DIR% ]"
    if !errorlevel! neq 0 (
        echo [INFO] Prima esecuzione: Copio i file nell'ambiente Linux per prestazioni ottimali...
        for /f "delims=" %%I in ('wsl wslpath -u "%CURRENT_DIR%"') do set LINUX_SRC_DIR=%%I
        wsl -e bash -c "cp -r '!LINUX_SRC_DIR!' %DEFAULT_WSL_DIR%"
        echo [INFO] Copia completata in %DEFAULT_WSL_DIR%.
    ) else (
        echo [INFO] Utilizzo il server gia' installato in %DEFAULT_WSL_DIR%.
        echo [INFO] (Nota: se hai modificato dei file qui su Windows, non avranno effetto. E' consigliato usare Install.bat per l'installazione e l'avvio.^)
    )
    set RUN_PATH=%DEFAULT_WSL_DIR%
) else (
    :: Esecuzione diretta da UNC path di WSL (\\wsl.localhost\...)
    for /f "delims=" %%I in ('wsl wslpath -u "%CURRENT_DIR%"') do set RUN_PATH=%%I
    if "!RUN_PATH!"=="" set RUN_PATH=%DEFAULT_WSL_DIR%
    echo [INFO] Esecuzione diretta da ambiente WSL in: !RUN_PATH!
)

echo.
echo Starting web container and host agent...
wsl -e bash -c "cd !RUN_PATH! && chmod +x *.sh utils/*.sh && ./utils/setup-web.sh && (explorer.exe http://localhost/index.html || true) && ./utils/host-agent.sh"

echo Dashboard closed.
pause
