@echo off
echo Compiling Process Priority Manager App...

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges are required to set process priority to Realtime.
    echo Requesting elevated privileges...

    :: Restart script with admin rights
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Check if .NET Framework is installed
where csc.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Error: C# compiler (csc.exe) not found.
    echo Please make sure .NET Framework is installed.
    pause
    exit /b 1
)

:: Compile the C# application
csc.exe /target:winexe /out:ProcessPriorityManagerApp.exe /reference:System.Windows.Forms.dll,System.Drawing.dll ProcessPriorityManagerApp.cs

if %ERRORLEVEL% NEQ 0 (
    echo Error: Compilation failed.
    pause
    exit /b 1
)

echo Compilation successful!
echo Starting the application...

:: Run the application
start ProcessPriorityManagerApp.exe

echo Application started. Look for the icon in the system tray.
pause
