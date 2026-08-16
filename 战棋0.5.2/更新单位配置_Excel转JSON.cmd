@echo off
setlocal

for %%I in ("%~dp0.") do set "PROJECT_ROOT=%%~fI"
set "SYNC_SCRIPT=%~dp0tools\config\SyncUnitConfig.ps1"

echo ================================================
echo   Silent Reckoning 1987 - Unit Config Updater
echo ================================================
echo.
echo Save and close unit_config.xlsx before updating.
echo Updating Excel unit data to game JSON...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SYNC_SCRIPT%" -ProjectRoot "%PROJECT_ROOT%"
set "SYNC_EXIT=%ERRORLEVEL%"

echo.
if "%SYNC_EXIT%"=="0" (
    echo [SUCCESS] Unit configuration has been updated.
    echo Output: data\units\unit_config.json
) else (
    echo [FAILED] Unit configuration was not updated.
    echo Close Excel, keep the original headers, and verify Microsoft Excel is installed.
)
echo.

if /I not "%~1"=="--no-pause" pause
exit /b %SYNC_EXIT%
