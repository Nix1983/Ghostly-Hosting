@echo off
setlocal
chcp 65001 >nul

if "%~1"=="" (
    echo Fehler: Du musst die Ziel-IP-Adresse angeben.
    echo Beispiel:
    echo   upload.bat 94.237.88.131
    exit /b 1
)

set TARGET_IP=%1
set REMOTE_PATH=/root/
set SSH_OPTS=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

echo == Upload zu %TARGET_IP% startet ==

:: Verzeichnis erstellen auf Zielserver
ssh %SSH_OPTS% root@%TARGET_IP% "mkdir -p %REMOTE_PATH%"

echo [1/4] Lade *.sh-Dateien hoch...
scp %SSH_OPTS% *.sh root@%TARGET_IP%:%REMOTE_PATH%/

echo [2/4] Lade .env-Datei hoch...
scp %SSH_OPTS% .env root@%TARGET_IP%:%REMOTE_PATH%/

echo [3/4] Lade lib/-Verzeichnis hoch...
scp %SSH_OPTS% -r lib root@%TARGET_IP%:%REMOTE_PATH%/

echo [4/4] Lade config/-Verzeichnis hoch...
scp %SSH_OPTS% -r config root@%TARGET_IP%:%REMOTE_PATH%/

echo.
echo Upload abgeschlossen.
echo.

