@echo off
title Microsoft Office Auto Uninstaller

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
echo   Microsoft Office Auto Uninstaller
echo ============================================================
echo.
echo  Running as Administrator... OK
echo  PC will REBOOT automatically when done.
echo.

:: ─── Run PS1 silently – no prompts, auto reboot ──────────────────────────────
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UninstallOffice.ps1" -Silent