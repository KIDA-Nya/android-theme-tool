@echo off
rem ============================================================
rem  ThemeTool - ColorOS local theme applier
rem
rem  Usage:
rem    * Double-click            -> open interactive menu
rem    * Drag a .theme onto this -> apply it directly (one step)
rem    * theme_tool.bat FILE     -> same as drag & drop
rem    * theme_tool.bat FILE -NoLock   -> extra args are passed through
rem ============================================================
setlocal
pushd "%~dp0"

if not exist "tools\apply_local_theme.ps1" (
    echo [x] tools\apply_local_theme.ps1 not found.
    echo     Keep this .bat next to the tools folder.
    pause
    popd
    exit /b 1
)

set "THEME=%~1"

if "%THEME%"=="" goto MENU

rem ---- one-step: apply the dropped file ----
if not exist "%THEME%" (
    echo [x] File not found: %THEME%
    pause
    popd
    exit /b 1
)

echo ============================================================
echo   Applying theme: %THEME%
echo ============================================================
shift
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\apply_local_theme.ps1" -Theme "%THEME%" %1 %2 %3 %4
goto DONE

:MENU
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\theme_console.ps1"

:DONE
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" (
    echo.
    echo [!] exited with code %RC%
    pause
)
exit /b %RC%
