# Process Priority Manager Installer
# This script installs the Process Priority Manager as a startup application

# Ensure running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script needs to be run as Administrator. Please restart with elevated privileges." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# Get the script directory
$scriptDir = $PSScriptRoot

# Create the startup shortcut
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path -Path $startupFolder -ChildPath "ProcessPriorityManager.lnk"

# Check if we have the C# app or need to use PowerShell script
$appPath = Join-Path -Path $scriptDir -ChildPath "ProcessPriorityManagerApp.exe"
$psScriptPath = Join-Path -Path $scriptDir -ChildPath "ProcessPriorityManager_Standalone.ps1"

if (Test-Path $appPath) {
    # Create shortcut to the C# app
    $targetPath = $appPath
    $iconPath = $appPath
    
    Write-Host "Creating startup shortcut for the C# application..." -ForegroundColor Cyan
} else {
    # Create shortcut to run the PowerShell script
    $targetPath = "powershell.exe"
    $arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$psScriptPath`""
    $iconPath = "powershell.exe"
    
    Write-Host "Creating startup shortcut for the PowerShell script..." -ForegroundColor Cyan
    
    # Make sure the standalone script exists
    if (-not (Test-Path $psScriptPath)) {
        # Run the main script to generate the standalone script
        $mainScriptPath = Join-Path -Path $scriptDir -ChildPath "ProcessPriorityManager.ps1"
        if (Test-Path $mainScriptPath) {
            Write-Host "Generating standalone script..." -ForegroundColor Cyan
            & $mainScriptPath
            # Choose option 5 (Exit without running)
            "5"
        } else {
            Write-Host "Error: Main script not found at $mainScriptPath" -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit
        }
    }
}

# Create the shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = $targetPath

if ($arguments) {
    $Shortcut.Arguments = $arguments
}

$Shortcut.IconLocation = $iconPath
$Shortcut.Description = "Process Priority Manager"
$Shortcut.WorkingDirectory = $scriptDir
$Shortcut.Save()

Write-Host "Shortcut created at: $shortcutPath" -ForegroundColor Green

# Create a scheduled task option
Write-Host "`nWould you like to create a scheduled task to run at system startup?" -ForegroundColor Cyan
Write-Host "This is recommended for better reliability and to ensure the tool runs with administrative privileges."
$createTask = Read-Host "Create scheduled task? (Y/N)"

if ($createTask -eq "Y" -or $createTask -eq "y") {
    Write-Host "Creating scheduled task..." -ForegroundColor Cyan
    
    if (Test-Path $appPath) {
        # Create task for the C# app
        $action = New-ScheduledTaskAction -Execute $appPath -WorkingDirectory $scriptDir
    } else {
        # Create task for the PowerShell script
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$psScriptPath`""
    }
    
    $trigger = New-ScheduledTaskTrigger -AtLogon
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -Hidden
    
    # Register the task
    Register-ScheduledTask -TaskName "ProcessPriorityManager" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    
    Write-Host "Scheduled task 'ProcessPriorityManager' created successfully." -ForegroundColor Green
}

Write-Host "`nInstallation complete!" -ForegroundColor Green
Write-Host "The Process Priority Manager will start automatically when you log in."
Write-Host "You can also run it manually using the provided scripts or application."
Read-Host "Press Enter to exit"
