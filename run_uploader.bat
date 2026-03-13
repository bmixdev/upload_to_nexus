@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 1251 >nul

set "SCRIPT_DIR=%~dp0"
set "CFG_FILE=%SCRIPT_DIR%run_uploader.cfg"
set "TMP_HTTP=%TEMP%\nexus_http_%RANDOM%_%RANDOM%.tmp"
set "TMP_ERR=%TEMP%\nexus_err_%RANDOM%_%RANDOM%.tmp"

set "REPO_URL="
set "REPO_PATH="
set "FILE_PATH="
set "NEXUS_USER="
set "NEXUS_PASS="
set "CONTINUE_ON_DELETE_403_404=1"
set "CURL_INSECURE=1"

call :log INFO "Шаг 1: старт сценария."

where curl >nul 2>nul
if errorlevel 1 (
    call :log ERROR "Утилита curl не найдена в PATH."
    echo [ОШИБКА] Утилита curl не найдена в PATH.
    echo Установите curl или используйте Windows 11 с доступным curl.exe.
    call :cleanup_tmp
    exit /b 1
)
call :log INFO "Шаг 2: проверка curl выполнена."

echo === Nexus Raw Uploader ^(BAT + curl^) ===
echo.

if exist "%CFG_FILE%" (
    call :log INFO "Шаг 3: найден файл конфигурации %CFG_FILE%"
    call :load_cfg "%CFG_FILE%"
) else (
    call :log WARN "Шаг 3: файл конфигурации не найден, будет интерактивный ввод."
)

if "%REPO_URL%"=="" (
    set /p "REPO_URL=URL репозитория (пример: http://localhost:8081/repository/my-raw): "
) else (
    call :log INFO "Параметр REPO_URL загружен из cfg."
)
if "%REPO_URL%"=="" (
    echo [ОШИБКА] Не заполнен URL репозитория.
    call :cleanup_tmp
    exit /b 1
)

if "%REPO_PATH%"=="" (
    set /p "REPO_PATH=Подпуть в репозитории (можно пусто, пример: releases/app): "
) else (
    call :log INFO "Параметр REPO_PATH загружен из cfg."
)

if "%FILE_PATH%"=="" (
    set /p "FILE_PATH=Полный путь к локальному файлу: "
) else (
    call :log INFO "Параметр FILE_PATH загружен из cfg."
)
if "%FILE_PATH%"=="" (
    echo [ОШИБКА] Не заполнен путь к файлу.
    call :cleanup_tmp
    exit /b 1
)
if not exist "%FILE_PATH%" (
    echo [ОШИБКА] Файл не найден: "%FILE_PATH%"
    call :cleanup_tmp
    exit /b 1
)

if "%NEXUS_USER%"=="" (
    set /p "NEXUS_USER=Пользователь Nexus: "
) else (
    call :log INFO "Параметр NEXUS_USER загружен из cfg."
)
if "%NEXUS_USER%"=="" (
    echo [ОШИБКА] Не заполнен пользователь Nexus.
    call :cleanup_tmp
    exit /b 1
)

if "%NEXUS_PASS%"=="" (
    echo ВНИМАНИЕ: в чистом BAT пароль вводится видимым текстом.
    set /p "NEXUS_PASS=Пароль Nexus: "
) else (
    call :log INFO "Параметр NEXUS_PASS загружен из cfg (значение скрыто)."
)
if "%NEXUS_PASS%"=="" (
    echo [ОШИБКА] Не заполнен пароль Nexus.
    call :cleanup_tmp
    exit /b 1
)

call :log INFO "Шаг 4: входные параметры получены и проверены."
call :log INFO "Режим CONTINUE_ON_DELETE_403_404=%CONTINUE_ON_DELETE_403_404%"
call :log INFO "Режим CURL_INSECURE=%CURL_INSECURE%"

set "CURL_SSL_ARG="
if "%CURL_INSECURE%"=="1" set "CURL_SSL_ARG=-k"

for %%F in ("%FILE_PATH%") do set "FILE_NAME=%%~nxF"
if "%FILE_NAME%"=="" (
    echo [ОШИБКА] Не удалось определить имя файла.
    call :cleanup_tmp
    exit /b 1
)

call :trim_trailing_slash REPO_URL
call :trim_slashes REPO_PATH

if "%REPO_PATH%"=="" (
    set "ARTIFACT_URL=%REPO_URL%/%FILE_NAME%"
) else (
    set "ARTIFACT_URL=%REPO_URL%/%REPO_PATH%/%FILE_NAME%"
)

call :log INFO "Шаг 5: целевой URL собран."
call :log INFO "Целевой URL: %ARTIFACT_URL%"
call :log INFO "Этап 1/2: DELETE предыдущего файла..."

call :log INFO "Шаг 6: отправка DELETE запроса."
set "DEL_CODE="
curl %CURL_SSL_ARG% -sS -o NUL -w "%%{http_code}" -u "%NEXUS_USER%:%NEXUS_PASS%" -X DELETE "%ARTIFACT_URL%" 1>"%TMP_HTTP%" 2>"%TMP_ERR%"
set "CURL_EXIT=%ERRORLEVEL%"
if exist "%TMP_HTTP%" set /p "DEL_CODE="<"%TMP_HTTP%"
if "%DEL_CODE%"=="" set "DEL_CODE=000"
if not "%CURL_EXIT%"=="0" (
    call :log WARN "curl на DELETE завершился с кодом %CURL_EXIT%."
    call :print_err_file
)
call :log INFO "Шаг 7: DELETE завершен с HTTP %DEL_CODE%."

if "%DEL_CODE%"=="403" (
    if "%CONTINUE_ON_DELETE_403_404%"=="1" (
        call :log WARN "DELETE вернул HTTP 403, продолжаем загрузку по правилу."
    ) else (
        call :log ERROR "DELETE вернул HTTP 403, продолжение отключено в cfg. Операция остановлена."
        call :cleanup_tmp
        exit /b 1
    )
) else if "%DEL_CODE%"=="404" (
    if "%CONTINUE_ON_DELETE_403_404%"=="1" (
        call :log WARN "DELETE вернул HTTP 404, продолжаем загрузку по правилу."
    ) else (
        call :log ERROR "DELETE вернул HTTP 404, продолжение отключено в cfg. Операция остановлена."
        call :cleanup_tmp
        exit /b 1
    )
) else (
    call :is_2xx "%DEL_CODE%"
    if errorlevel 1 (
        call :log ERROR "DELETE завершился ошибкой HTTP %DEL_CODE%. Операция остановлена."
        call :cleanup_tmp
        exit /b 1
    )
    call :log INFO "DELETE выполнен успешно, HTTP %DEL_CODE%."
)

call :log INFO "Этап 2/2: UPLOAD нового файла..."
call :log INFO "Шаг 8: отправка UPLOAD запроса."
set "UP_CODE="
curl %CURL_SSL_ARG% -sS -o NUL -w "%%{http_code}" -u "%NEXUS_USER%:%NEXUS_PASS%" --upload-file "%FILE_PATH%" "%ARTIFACT_URL%" 1>"%TMP_HTTP%" 2>"%TMP_ERR%"
set "CURL_EXIT=%ERRORLEVEL%"
if exist "%TMP_HTTP%" set /p "UP_CODE="<"%TMP_HTTP%"
if "%UP_CODE%"=="" set "UP_CODE=000"
if not "%CURL_EXIT%"=="0" (
    call :log WARN "curl на UPLOAD завершился с кодом %CURL_EXIT%."
    call :print_err_file
)
call :log INFO "Шаг 9: UPLOAD завершен с HTTP %UP_CODE%."

call :is_2xx "%UP_CODE%"
if errorlevel 1 (
    call :log ERROR "UPLOAD завершился ошибкой HTTP %UP_CODE%."
    call :cleanup_tmp
    exit /b 1
)

call :log INFO "UPLOAD успешно завершен, HTTP %UP_CODE%."
call :log INFO "Готово."
call :cleanup_tmp
exit /b 0

:load_cfg
set "_cfg=%~1"
for /f "usebackq tokens=1,* delims==" %%A in ("%_cfg%") do (
    set "_k=%%~A"
    set "_v=%%~B"
    if not "%%~A"=="" (
        if /i not "%%~A"=="REM" (
            if not "%%~A:~0,1"=="#" (
                if /i "%%~A"=="REPO_URL" set "REPO_URL=%%~B"
                if /i "%%~A"=="REPO_PATH" set "REPO_PATH=%%~B"
                if /i "%%~A"=="FILE_PATH" set "FILE_PATH=%%~B"
                if /i "%%~A"=="NEXUS_USER" set "NEXUS_USER=%%~B"
                if /i "%%~A"=="NEXUS_PASS" set "NEXUS_PASS=%%~B"
                if /i "%%~A"=="CONTINUE_ON_DELETE_403_404" set "CONTINUE_ON_DELETE_403_404=%%~B"
                if /i "%%~A"=="CURL_INSECURE" set "CURL_INSECURE=%%~B"
            )
        )
    )
)

if not "%CONTINUE_ON_DELETE_403_404%"=="1" set "CONTINUE_ON_DELETE_403_404=0"
if not "%CURL_INSECURE%"=="1" set "CURL_INSECURE=0"
goto :eof

:print_err_file
if exist "%TMP_ERR%" (
    for /f "usebackq delims=" %%E in ("%TMP_ERR%") do (
        if not "%%E"=="" call :log WARN "curl stderr: %%E"
    )
)
goto :eof

:cleanup_tmp
if exist "%TMP_HTTP%" del /q "%TMP_HTTP%" >nul 2>nul
if exist "%TMP_ERR%" del /q "%TMP_ERR%" >nul 2>nul
goto :eof

:trim_trailing_slash
call set "_v=%%%~1%%"
if "%_v%"=="" goto :eof
:trim_trailing_loop
if "%_v:~-1%"=="/" set "_v=%_v:~0,-1%" & goto trim_trailing_loop
set "%~1=%_v%"
goto :eof

:trim_slashes
call set "_v=%%%~1%%"
if "%_v%"=="" goto :eof
:trim_leading_loop
if "%_v:~0,1%"=="/" set "_v=%_v:~1%" & goto trim_leading_loop
:trim_trailing_loop2
if "%_v:~-1%"=="/" set "_v=%_v:~0,-1%" & goto trim_trailing_loop2
set "%~1=%_v%"
goto :eof

:is_2xx
set "_code=%~1"
if "%_code:~0,1%"=="2" exit /b 0
exit /b 1

:log
set "_lvl=%~1"
set "_msg=%~2"
echo [%date% %time:~0,8%] [%_lvl%] %_msg%
goto :eof
