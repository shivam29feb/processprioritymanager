@echo off
echo Starting Process Priority Manager...

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges are required to set process priority to Realtime.
    echo Requesting elevated privileges...

    :: Restart script with admin rights
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Run the PowerShell script
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0ProcessPriorityManager.ps1"
pause
