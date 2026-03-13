@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "HTA_FILE=%SCRIPT_DIR%nexus_uploader.hta"

if not exist "%HTA_FILE%" (
    echo [ОШИБКА] Не найден файл формы: "%HTA_FILE%"
    echo Проверьте, что run_uploader.bat и nexus_uploader.hta лежат в одной папке.
    exit /b 1
)

start "" mshta.exe "%HTA_FILE%"
exit /b 0

