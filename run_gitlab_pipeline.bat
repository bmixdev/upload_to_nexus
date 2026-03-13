@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 1251 >nul

set "SCRIPT_DIR=%~dp0"
set "CFG_FILE=%SCRIPT_DIR%run_gitlab_pipeline.cfg"
set "TMP_HTTP=%TEMP%\gitlab_http_%RANDOM%_%RANDOM%.tmp"
set "TMP_BODY=%TEMP%\gitlab_body_%RANDOM%_%RANDOM%.tmp"

set "GITLAB_URL="
set "PROJECT_ID="
set "REF="
set "AUTH_MODE=TRIGGER"
set "TRIGGER_TOKEN="
set "PRIVATE_TOKEN="
set "INSECURE_SSL=1"

for /L %%I in (1,1,10) do (
    set "VAR%%I_KEY="
    set "VAR%%I_VALUE="
)

call :log INFO "Шаг 1: старт вызова GitLab pipeline."

where curl >nul 2>nul
if errorlevel 1 (
    call :log ERROR "curl не найден в PATH."
    call :finish 1
)

if exist "%CFG_FILE%" (
    call :log INFO "Шаг 2: загружаю конфиг %CFG_FILE%"
    call :load_cfg "%CFG_FILE%"
) else (
    call :log WARN "Шаг 2: конфиг не найден, будет интерактивный ввод."
)

if "%GITLAB_URL%"=="" set /p "GITLAB_URL=GitLab URL (пример: https://gitlab.example.com): "
if "%PROJECT_ID%"=="" set /p "PROJECT_ID=Project ID (пример: 123): "
if "%REF%"=="" set /p "REF=Ref (ветка/тег, пример: main): "

if /I not "%AUTH_MODE%"=="TRIGGER" if /I not "%AUTH_MODE%"=="PRIVATE" set "AUTH_MODE=TRIGGER"

if /I "%AUTH_MODE%"=="TRIGGER" (
    if "%TRIGGER_TOKEN%"=="" set /p "TRIGGER_TOKEN=Trigger token: "
) else (
    if "%PRIVATE_TOKEN%"=="" set /p "PRIVATE_TOKEN=Private token: "
)

if "%GITLAB_URL%"=="" (
    call :log ERROR "Не заполнен GITLAB_URL."
    call :finish 1
)
if "%PROJECT_ID%"=="" (
    call :log ERROR "Не заполнен PROJECT_ID."
    call :finish 1
)
if "%REF%"=="" (
    call :log ERROR "Не заполнен REF."
    call :finish 1
)

if /I "%AUTH_MODE%"=="TRIGGER" (
    if "%TRIGGER_TOKEN%"=="" (
        call :log ERROR "Не заполнен TRIGGER_TOKEN."
        call :finish 1
    )
) else (
    if "%PRIVATE_TOKEN%"=="" (
        call :log ERROR "Не заполнен PRIVATE_TOKEN."
        call :finish 1
    )
)

set "CURL_SSL_ARG="
if "%INSECURE_SSL%"=="1" set "CURL_SSL_ARG=-k"

call :trim_trailing_slash GITLAB_URL

if /I "%AUTH_MODE%"=="TRIGGER" (
    set "API_URL=%GITLAB_URL%/api/v4/projects/%PROJECT_ID%/trigger/pipeline"
) else (
    set "API_URL=%GITLAB_URL%/api/v4/projects/%PROJECT_ID%/pipeline"
)

set "VAR_ARGS="
call :build_var_args

call :log INFO "Шаг 3: endpoint = %API_URL%"
call :log INFO "Шаг 4: запуск POST запроса в GitLab..."

if /I "%AUTH_MODE%"=="TRIGGER" (
    curl %CURL_SSL_ARG% --progress-bar -o "%TMP_BODY%" -w "%%{http_code}" -X POST "%API_URL%" --form "token=%TRIGGER_TOKEN%" --form "ref=%REF%" %VAR_ARGS% >"%TMP_HTTP%"
) else (
    curl %CURL_SSL_ARG% --progress-bar -o "%TMP_BODY%" -w "%%{http_code}" -X POST "%API_URL%" --header "PRIVATE-TOKEN: %PRIVATE_TOKEN%" --form "ref=%REF%" %VAR_ARGS% >"%TMP_HTTP%"
)
set "CURL_EXIT=%ERRORLEVEL%"

set "HTTP_CODE="
if exist "%TMP_HTTP%" set /p "HTTP_CODE="<"%TMP_HTTP%"
if "%HTTP_CODE%"=="" set "HTTP_CODE=000"

if not "%CURL_EXIT%"=="0" (
    call :log WARN "curl завершился с кодом %CURL_EXIT%."
)

call :log INFO "Шаг 5: HTTP код ответа = %HTTP_CODE%"
call :log INFO "Тело ответа GitLab:"
if exist "%TMP_BODY%" (
    type "%TMP_BODY%"
) else (
    echo [пусто]
)

call :is_2xx "%HTTP_CODE%"
if errorlevel 1 (
    call :log ERROR "Запуск pipeline завершился с ошибкой HTTP %HTTP_CODE%."
    call :cleanup
    call :finish 1
)

call :log INFO "Pipeline успешно запущен."
call :cleanup
call :finish 0

:build_var_args
setlocal EnableDelayedExpansion
for /L %%I in (1,1,10) do (
    call set "_K=%%VAR%%I_KEY%%"
    call set "_V=%%VAR%%I_VALUE%%"
    if not "!_K!"=="" (
        set "VAR_ARGS=!VAR_ARGS! --form "variables[!_K!]=!_V!""
    )
)
endlocal & set "VAR_ARGS=%VAR_ARGS%"
goto :eof

:load_cfg
set "_cfg=%~1"
for /f "usebackq tokens=1,* delims==" %%A in ("%_cfg%") do (
    if not "%%~A"=="" (
        if /i not "%%~A"=="REM" (
            if not "%%~A:~0,1"=="#" (
                call :set_cfg "%%~A" "%%~B"
            )
        )
    )
)
if /I not "%AUTH_MODE%"=="TRIGGER" if /I not "%AUTH_MODE%"=="PRIVATE" set "AUTH_MODE=TRIGGER"
if not "%INSECURE_SSL%"=="1" set "INSECURE_SSL=0"
goto :eof

:set_cfg
set "_KEY=%~1"
set "_VAL=%~2"
if /I "%_KEY%"=="GITLAB_URL" set "GITLAB_URL=%_VAL%"
if /I "%_KEY%"=="PROJECT_ID" set "PROJECT_ID=%_VAL%"
if /I "%_KEY%"=="REF" set "REF=%_VAL%"
if /I "%_KEY%"=="AUTH_MODE" set "AUTH_MODE=%_VAL%"
if /I "%_KEY%"=="TRIGGER_TOKEN" set "TRIGGER_TOKEN=%_VAL%"
if /I "%_KEY%"=="PRIVATE_TOKEN" set "PRIVATE_TOKEN=%_VAL%"
if /I "%_KEY%"=="INSECURE_SSL" set "INSECURE_SSL=%_VAL%"
for /L %%I in (1,1,10) do (
    if /I "%_KEY%"=="VAR%%I_KEY" set "VAR%%I_KEY=%_VAL%"
    if /I "%_KEY%"=="VAR%%I_VALUE" set "VAR%%I_VALUE=%_VAL%"
)
goto :eof

:trim_trailing_slash
call set "_v=%%%~1%%"
if "%_v%"=="" goto :eof
:trim_loop
if "%_v:~-1%"=="/" set "_v=%_v:~0,-1%" & goto trim_loop
set "%~1=%_v%"
goto :eof

:is_2xx
set "_code=%~1"
if "%_code:~0,1%"=="2" exit /b 0
exit /b 1

:cleanup
if exist "%TMP_HTTP%" del /q "%TMP_HTTP%" >nul 2>nul
if exist "%TMP_BODY%" del /q "%TMP_BODY%" >nul 2>nul
goto :eof

:log
echo [%date% %time:~0,8%] [%~1] %~2
goto :eof

:finish
echo.
echo Нажмите любую клавишу для выхода...
pause >nul
exit /b %~1
