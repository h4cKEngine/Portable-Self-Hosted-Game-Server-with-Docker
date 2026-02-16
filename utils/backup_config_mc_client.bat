@echo off
setlocal enabledelayedexpansion

:: --- CONFIGURAZIONE PERCORSI ---
set "SOURCE=%APPDATA%\.minecraft"
set "LOG_FILE=%SOURCE%\logs\latest.log"

echo ======================================================
echo           MC LIGHT BACKUP - AUTO-DETECTION
echo ======================================================
echo [!] AVVISO: Affinche il backup sia completo e le 
echo     versioni vengano rilevate, Minecraft deve essere
echo     stato avviato correttamente almeno una volta
echo     con le mod caricate.
echo ======================================================
echo.

:: --- CONTROLLO LOG ---
if not exist "%LOG_FILE%" (
    echo [ERRORE] File di log non trovato in:
    echo "%LOG_FILE%"
    echo.
    echo Per risolvere: Avvia il gioco con il profilo 
    echo NeoForge/Forge, raggiungi il menu principale e chiudi.
    echo.
    pause
    exit /b
)

:: --- AUTO-DISCOVERY DELLE VERSIONI ---
echo [+] Rilevamento versioni dal file di log...

:: Estrazione Minecraft Version
for /f "delims=" %%i in ('powershell -NoProfile -Command "$log = Get-Content '%LOG_FILE%' -First 1; if($log -match '--fml.mcVersion, ([^,\]\s]+)'){write-output $Matches[1]}"') do set "MC_VER=%%i"

:: Estrazione Loader Version (NeoForge o Forge)
for /f "delims=" %%i in ('powershell -NoProfile -Command "$log = Get-Content '%LOG_FILE%' -First 1; if($log -match '--fml.neoForgeVersion, ([^,\]\s]+)'){write-output 'NeoForge-' + $Matches[1]} elseif($log -match '--fml.forgeVersion, ([^,\]\s]+)'){write-output 'Forge-' + $Matches[1]}"') do set "FORGE_VER=%%i"

:: Fallback di sicurezza
if "%MC_VER%"=="" (
    set "MC_VER=UnknownMC"
    echo [!] ATTENZIONE: Versione Minecraft non rilevata.
)
if "%FORGE_VER%"=="" (
    set "FORGE_VER=UnknownLoader"
    echo [!] ATTENZIONE: Versione Loader non rilevata.
)

:: --- CONFIGURAZIONE BACKUP ---
set "DEST_BASE=%USERPROFILE%\Desktop\MC_Light_Backup"
set "TIMESTAMP=%date:~-4,4%-%date:~-7,2%-%date:~-10,2%_%time:~0,2%-%time:~3,2%"
set "TIMESTAMP=%TIMESTAMP: =0%"
set "BACKUP_PATH=%DEST_BASE%\Backup_%TIMESTAMP%"
set "MODLIST_FILE=mods_list_MC%MC_VER%_%FORGE_VER%.txt"

echo.
echo [+] Rilevato: MC %MC_VER% ^| %FORGE_VER%
echo.

:: Verifica Robocopy
where robocopy >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERRORE] Robocopy non trovato.
    pause
    exit /b
)

:: Creazione cartella
if not exist "%BACKUP_PATH%" mkdir "%BACKUP_PATH%"

:: --- GENERAZIONE LISTA MOD ---
echo [+] Generazione %MODLIST_FILE%...
echo # Elenco Mod installate al %date% %time% > "%BACKUP_PATH%\%MODLIST_FILE%"
echo # Minecraft Version: %MC_VER% >> "%BACKUP_PATH%\%MODLIST_FILE%"
echo # Loader Version: %FORGE_VER% >> "%BACKUP_PATH%\%MODLIST_FILE%"
echo # ------------------------------------------ >> "%BACKUP_PATH%\%MODLIST_FILE%"
dir /b "%SOURCE%\mods\*.jar" >> "%BACKUP_PATH%\%MODLIST_FILE%"

:: --- BACKUP CONFIGURAZIONI ---
echo [+] Backup cartella Config...
robocopy "%SOURCE%\config" "%BACKUP_PATH%\config" /E /MT /R:3 /W:5 /NFL /NDL > nul

:: --- FILE EXTRA ---
echo [+] Backup file opzioni e server...
copy "%SOURCE%\options.txt" "%BACKUP_PATH%\" > nul
copy "%SOURCE%\servers.dat" "%BACKUP_PATH%\" > nul

echo ------------------------------------------------------
echo [OK] Backup completato con successo!
echo File: %MODLIST_FILE%
echo In: %BACKUP_PATH%
echo ------------------------------------------------------
pause