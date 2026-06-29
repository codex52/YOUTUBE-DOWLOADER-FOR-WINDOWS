@echo off
cd /d "%~dp0"
chcp 65001 >nul 2>&1
title TAREK X DOWNLOADER
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Downloader.ps1"
echo.
echo Press any key to close this window...
pause >nul
