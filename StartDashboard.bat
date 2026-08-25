@echo off
setlocal EnableDelayedExpansion

:: Abilita il supporto per i percorsi di rete (UNC) come \\wsl.localhost\...
pushd "%~dp0"

set CONFIG_FILE=utils\wsl_path_config.txt

if not exist "%CONFIG_FILE%" (
    echo ==========================================================
    echo                 FIRST TIME SETUP
    echo ==========================================================
    echo Welcome! To make this dashboard portable, please enter the
    echo full WSL path to this project folder.
    echo.
    echo Example: ~/proj/Portable-Self-Hosted-Game-Server-with-Docker
    echo Or: /home/username/Portable-Self-Hosted-Game-Server-with-Docker
    echo.
    set /p WSL_PATH="Enter WSL Path: "
    
    :: Convert backslashes to forward slashes just in case the user types Windows paths
    set WSL_PATH=!WSL_PATH:\=/!
    
    echo !WSL_PATH!> "%CONFIG_FILE%"
    echo Configuration saved to %CONFIG_FILE%.
    echo.
)

:: Read the path from config file
set /p WSL_PATH=<"%CONFIG_FILE%"
:: Ensure forward slashes even if read from file
set WSL_PATH=!WSL_PATH:\=/!

echo ==========================================================
echo       STARTING GAME SERVER DASHBOARD (WSL Bridge)
echo ==========================================================
echo Project Path: %WSL_PATH%
echo Starting web container and host agent...
wsl -e bash -c "cd %WSL_PATH% && chmod +x *.sh utils/*.sh && ./setup-web.sh && (explorer.exe http://localhost/index.html || true) && ./utils/host-agent.sh"
echo Dashboard closed.
pause
