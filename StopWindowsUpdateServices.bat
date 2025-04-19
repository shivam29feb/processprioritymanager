@echo off
echo Stopping Windows Update Services...

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges are required to stop Windows services.
    echo Requesting elevated privileges...
    
    :: Restart script with admin rights
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Run the PowerShell script
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0StopWindowsUpdateServices.ps1"
pause
