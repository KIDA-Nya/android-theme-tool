@echo off
setlocal
pushd "%~dp0"

set "ENTRY=tools\theme_console.ps1"
if not exist "%ENTRY%" (
    echo [x] %ENTRY% not found.
    echo     Keep this .bat next to the tools folder.
    pause
    popd
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%ENTRY%" %*
set "RC=%ERRORLEVEL%"

popd
if not "%RC%"=="0" (
    echo.
    echo [!] exited with code %RC%
    pause
)
exit /b %RC%