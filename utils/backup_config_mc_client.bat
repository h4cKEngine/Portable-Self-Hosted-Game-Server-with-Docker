@echo off
setlocal enabledelayedexpansion

:: --- PATH CONFIGURATION ---
set "SOURCE=%APPDATA%\.minecraft"
set "LOG_FILE=%SOURCE%\logs\latest.log"

echo ======================================================
echo           MC LIGHT BACKUP - AUTO-DETECTION
echo ======================================================
echo [!] WARNING: For the backup to be complete and
echo     versions to be detected, Minecraft must have been
echo     started successfully at least once
echo     with mods loaded.
echo ======================================================
echo.

:: --- LOG CHECK ---
if not exist "%LOG_FILE%" (
    echo [ERROR] Log file not found at:
    echo "%LOG_FILE%"
    echo.
    echo To resolve: Start the game with the NeoForge/Forge
    echo profile, reach the main menu and close.
    echo.
    pause
    exit /b
)

:: --- VERSION AUTO-DISCOVERY ---
echo [+] Detecting versions from log file...

:: Minecraft Version Extraction
for /f "delims=" %%i in ('powershell -NoProfile -Command "$log = Get-Content '%LOG_FILE%' -First 1; if($log -match '--fml.mcVersion, ([^,\]\s]+)'){write-output $Matches[1]}"') do set "MC_VER=%%i"

:: Loader Version Extraction (NeoForge or Forge)
for /f "delims=" %%i in ('powershell -NoProfile -Command "$log = Get-Content '%LOG_FILE%' -First 1; if($log -match '--fml.neoForgeVersion, ([^,\]\s]+)'){write-output 'NeoForge-' + $Matches[1]} elseif($log -match '--fml.forgeVersion, ([^,\]\s]+)'){write-output 'Forge-' + $Matches[1]}"') do set "FORGE_VER=%%i"

:: Safety Fallback
if "%MC_VER%"=="" (
    set "MC_VER=UnknownMC"
    echo [!] WARNING: Minecraft Version not detected.
)
if "%FORGE_VER%"=="" (
    set "FORGE_VER=UnknownLoader"
    echo [!] WARNING: Loader Version not detected.
)

:: --- BACKUP CONFIGURATION ---
set "DEST_BASE=%USERPROFILE%\Desktop\MC_Light_Backup"
set "TIMESTAMP=%date:~-4,4%-%date:~-7,2%-%date:~-10,2%_%time:~0,2%-%time:~3,2%"
set "TIMESTAMP=%TIMESTAMP: =0%"
set "BACKUP_PATH=%DEST_BASE%\Backup_%TIMESTAMP%"
set "MODLIST_FILE=mods_list_MC%MC_VER%_%FORGE_VER%.txt"

echo.
echo [+] Detected: MC %MC_VER% ^| %FORGE_VER%
echo.

:: Robocopy check
where robocopy >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Robocopy not found.
    pause
    exit /b
)

:: Folder creation
if not exist "%BACKUP_PATH%" mkdir "%BACKUP_PATH%"

:: --- MOD LIST GENERATION ---
echo [+] Generating %MODLIST_FILE%...
echo # List of Mods installed on %date% %time% > "%BACKUP_PATH%\%MODLIST_FILE%"
echo # Minecraft Version: %MC_VER% >> "%BACKUP_PATH%\%MODLIST_FILE%"
echo # Loader Version: %FORGE_VER% >> "%BACKUP_PATH%\%MODLIST_FILE%"
echo # ------------------------------------------ >> "%BACKUP_PATH%\%MODLIST_FILE%"
dir /b "%SOURCE%\mods\*.jar" >> "%BACKUP_PATH%\%MODLIST_FILE%"

:: --- CONFIGURATIONS BACKUP ---
echo [+] Backup Config folder...
robocopy "%SOURCE%\config" "%BACKUP_PATH%\config" /E /MT /R:3 /W:5 /NFL /NDL > nul

:: --- EXTRA FILES ---
echo [+] Backup options and server files...
copy "%SOURCE%\options.txt" "%BACKUP_PATH%\" > nul
copy "%SOURCE%\servers.dat" "%BACKUP_PATH%\" > nul

echo ------------------------------------------------------
echo [OK] Backup completed successfully!
echo File: %MODLIST_FILE%
echo In: %BACKUP_PATH%
echo ------------------------------------------------------
pause