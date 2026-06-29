@echo off
echo ==========================================
echo YouTube Downloader Build Verification
echo ==========================================
echo.
echo Checking Downloader.ps1...
if exist "Downloader.ps1" (
    echo [OK] Downloader.ps1 found.
) else (
    echo [ERROR] Downloader.ps1 is missing!
)
echo Checking run.bat...
if exist "run.bat" (
    echo [OK] run.bat found.
) else (
    echo [ERROR] run.bat is missing!
)
echo.
echo Done checking workspace structure.
pause
