@echo off
title Microsoft Office Auto Installer

:: ─── Check if already running as Administrator ───────────────────────────────
net session >nul 2>&1
if %errorLevel% == 0 goto :RUN

:: ─── Not admin – re-launch self elevated ─────────────────────────────────────
echo Requesting Administrator privileges...
powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:RUN
cls
echo ============================================================
echo   Microsoft Office Auto Installer (ODT)
echo ============================================================
echo.
echo Running as Administrator... OK
echo.

:: ─── Change to the script directory ─────────────────────────────────────────
cd /d "%~dp0"

:: ─── Locate ODT setup.exe and configuration file ────────────────────────────
set "SETUP_EXE=setup.exe"
set "CONFIG_XML=configuration.xml"

if not exist "%SETUP_EXE%" (
    echo [ERROR] setup.exe not found in %~dp0
    echo Please place the Office Deployment Tool executable here.
    pause
    exit /b 1
)

if not exist "%CONFIG_XML%" (
    echo [ERROR] %CONFIG_XML% not found in %~dp0
    echo Please place your ODT configuration XML file here.
    pause
    exit /b 1
)

:: ─── Optional: kill any running Office processes before install ─────────────
echo Stopping any running Office processes...
for %%p in (WINWORD EXCEL POWERPNT OUTLOOK ONENOTE MSPUB MSACCESS) do (
    taskkill /f /im %%p.exe 2>nul >nul
)
echo Done.

:: ─── Run ODT to install Office ───────────────────────────────────────────────
echo.
echo Starting Office installation using:
echo   Setup: %SETUP_EXE%
echo   Config: %CONFIG_XML%
echo.
echo This may take several minutes. Please wait...

"%SETUP_EXE%" /configure "%CONFIG_XML%"

if %errorLevel% equ 0 (
    echo.
    echo ============================================================
    echo   Installation completed successfully.
    echo ============================================================
) else (
    echo.
    echo ============================================================
    echo   Installation failed with error code %errorLevel%.
    echo   Check the log files in %TEMP%\ODT*.log
    echo ============================================================
)

echo.
echo Press any key to exit...
pause >nul
exit /b %errorLevel%