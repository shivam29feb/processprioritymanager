# ProcessPriorityManager.ps1
# This script monitors for PowerShell and OpenConsole processes and sets their priority to Realtime

# Check if running as administrator
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not running as administrator, restart with elevated privileges
if (-not (Test-Administrator)) {
    Write-Host "This script requires administrator privileges to set process priority to Realtime." -ForegroundColor Yellow
    Write-Host "Restarting with elevated privileges..." -ForegroundColor Yellow

    # Restart the script with elevated privileges
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Function to set process priority to Realtime
function Set-ProcessToRealtime {
    param (
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process
    )

    try {
        # Check if the process is still running
        if (!$Process.HasExited) {
            # Get the current priority
            $currentPriority = $Process.PriorityClass

            # Only change if not already set to Realtime
            if ($currentPriority -ne [System.Diagnostics.ProcessPriorityClass]::RealTime) {
                Write-Host "Setting process $($Process.ProcessName) (ID: $($Process.Id)) priority to Realtime"
                $Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                Write-Host "Successfully set priority for $($Process.ProcessName) (ID: $($Process.Id))" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "Error setting priority for process $($Process.ProcessName) (ID: $($Process.Id)): $_" -ForegroundColor Red
    }
}

# Function to find and set priority for target processes
function Update-ProcessPriorities {
    # Get all PowerShell and OpenConsole processes
    $targetProcesses = @(
        Get-Process -Name "powershell" -ErrorAction SilentlyContinue
        Get-Process -Name "powershell_ise" -ErrorAction SilentlyContinue
        Get-Process -Name "pwsh" -ErrorAction SilentlyContinue
        Get-Process -Name "OpenConsole" -ErrorAction SilentlyContinue
        Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
    )

    # Set priority for each process
    foreach ($process in $targetProcesses) {
        Set-ProcessToRealtime -Process $process
    }
}

# Function to create a background job that monitors for new processes
function Start-ProcessMonitor {
    # Create a script block for the background job
    $monitorScript = {
        # Keep track of processes we've already set
        $processedIds = @{}

        while ($true) {
            # Get all target processes
            $targetProcesses = @(
                Get-Process -Name "powershell" -ErrorAction SilentlyContinue
                Get-Process -Name "powershell_ise" -ErrorAction SilentlyContinue
                Get-Process -Name "pwsh" -ErrorAction SilentlyContinue
                Get-Process -Name "OpenConsole" -ErrorAction SilentlyContinue
                Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
            )

            # Process each target
            foreach ($process in $targetProcesses) {
                # Check if we've already processed this ID
                if (-not $processedIds.ContainsKey($process.Id)) {
                    try {
                        # Set priority to Realtime
                        if (!$process.HasExited) {
                            $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                            Write-Output "Set priority for $($process.ProcessName) (ID: $($process.Id)) to Realtime"

                            # Mark as processed
                            $processedIds[$process.Id] = $true
                        }
                    }
                    catch {
                        Write-Output "Error setting priority for process $($process.ProcessName) (ID: $($process.Id)): $_"
                    }
                }
            }

            # Clean up processed IDs for processes that no longer exist
            $runningIds = $targetProcesses | ForEach-Object { $_.Id }
            $keysToRemove = @()

            foreach ($key in $processedIds.Keys) {
                if ($key -notin $runningIds) {
                    $keysToRemove += $key
                }
            }

            foreach ($key in $keysToRemove) {
                $processedIds.Remove($key)
            }

            # Wait before checking again
            Start-Sleep -Seconds 2
        }
    }

    # Start the background job
    $job = Start-Job -ScriptBlock $monitorScript
    return $job
}

# Function to create a Windows service using NSSM (Non-Sucking Service Manager)
function Install-AsService {
    param (
        [string]$ServiceName = "ProcessPriorityManager",
        [string]$ScriptPath
    )

    # Check if NSSM is available
    $nssmPath = "C:\Windows\System32\nssm.exe"
    if (-not (Test-Path $nssmPath)) {
        Write-Host "NSSM not found. Please install NSSM to create a Windows service." -ForegroundColor Yellow
        Write-Host "You can download it from: https://nssm.cc/download" -ForegroundColor Yellow
        return $false
    }

    # Create the service
    try {
        $powershellPath = (Get-Command powershell).Source
        $arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""

        # Remove service if it already exists
        & $nssmPath stop $ServiceName 2>$null
        & $nssmPath remove $ServiceName confirm 2>$null

        # Install the service
        & $nssmPath install $ServiceName $powershellPath $arguments
        & $nssmPath set $ServiceName DisplayName "Process Priority Manager"
        & $nssmPath set $ServiceName Description "Monitors PowerShell and OpenConsole processes and sets their priority to Realtime"
        & $nssmPath set $ServiceName Start SERVICE_AUTO_START

        # Start the service
        & $nssmPath start $ServiceName

        Write-Host "Service '$ServiceName' installed and started successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error installing service: $_" -ForegroundColor Red
        return $false
    }
}

# Function to create a scheduled task that runs at startup
function Install-AsScheduledTask {
    param (
        [string]$TaskName = "ProcessPriorityManager",
        [string]$ScriptPath
    )

    try {
        # Create action to run PowerShell with the script
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`""

        # Create trigger for system startup
        $trigger = New-ScheduledTaskTrigger -AtStartup

        # Create principal to run with highest privileges
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -Hidden

        # Register the task
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

        Write-Host "Scheduled task '$TaskName' created successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error creating scheduled task: $_" -ForegroundColor Red
        return $false
    }
}

# Create a standalone script that can be run directly
function Create-StandaloneScript {
    param (
        [string]$OutputPath
    )

    $scriptContent = @"
# ProcessPriorityManager - Standalone Script
# This script monitors for PowerShell and OpenConsole processes and sets their priority to Realtime
# It can also stop Windows Update related services

# Check if running as administrator
function Test-Administrator {
    `$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return `$currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not running as administrator, restart with elevated privileges
if (-not (Test-Administrator)) {
    Write-Host "This script requires administrator privileges to set process priority to Realtime." -ForegroundColor Yellow
    Write-Host "Restarting with elevated privileges..." -ForegroundColor Yellow

    # Restart the script with elevated privileges
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `\"`$PSCommandPath`\"" -Verb RunAs
    exit
}

# Function to stop Windows Update services
function Stop-WindowsUpdateServices {
    # List of Windows Update related services to stop
    `$updateServices = @(
        "wuauserv",           # Windows Update
        "UsoSvc",             # Update Orchestrator Service
        "DoSvc",              # Delivery Optimization
        "WaaSMedicSvc"        # Windows Update Medic Service
    )

    Write-Host "=== Stopping Windows Update Services ===" -ForegroundColor Cyan

    foreach (`$service in `$updateServices) {
        try {
            `$svc = Get-Service -Name `$service -ErrorAction Stop

            # Get current status
            `$currentStatus = `$svc.Status
            `$currentStartType = (Get-Service -Name `$service).StartType

            Write-Host "Service: `$(`$svc.DisplayName) (`$service)" -ForegroundColor Cyan
            Write-Host "  Current Status: `$currentStatus" -ForegroundColor Gray
            Write-Host "  Current Start Type: `$currentStartType" -ForegroundColor Gray

            # Stop the service if it's running
            if (`$currentStatus -eq "Running") {
                Write-Host "  Stopping service..." -ForegroundColor Yellow
                Stop-Service -Name `$service -Force -ErrorAction Stop
                Write-Host "  Service stopped successfully." -ForegroundColor Green
            }
            else {
                Write-Host "  Service is already stopped." -ForegroundColor Green
            }

            # Set service to disabled
            if (`$currentStartType -ne "Disabled") {
                Write-Host "  Setting service to disabled..." -ForegroundColor Yellow
                Set-Service -Name `$service -StartupType Disabled -ErrorAction Stop
                Write-Host "  Service set to disabled." -ForegroundColor Green
            }
            else {
                Write-Host "  Service is already disabled." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  Error processing service `$service`: `$_" -ForegroundColor Red
        }

        Write-Host ""
    }

    Write-Host "Windows Update services processing completed." -ForegroundColor Cyan
}

# Ask if user wants to stop Windows Update services
Write-Host "Would you like to stop Windows Update services?" -ForegroundColor Cyan
Write-Host "This will stop and disable the following services:"
Write-Host "- Windows Update"
Write-Host "- Update Orchestrator"
Write-Host "- Delivery Optimization"
Write-Host "- Windows Update Medic Service"

`$stopUpdateServices = Read-Host "Stop Windows Update services? (Y/N)"

if (`$stopUpdateServices -eq "Y" -or `$stopUpdateServices -eq "y") {
    Stop-WindowsUpdateServices
}

# Keep track of processes we've already set
`$processedIds = @{}

Write-Host "Process Priority Manager started. Monitoring for PowerShell and OpenConsole processes..."
Write-Host "Press Ctrl+C to stop the script."

try {
    while (`$true) {
        # Get all target processes
        `$targetProcesses = @(
            Get-Process -Name "powershell" -ErrorAction SilentlyContinue
            Get-Process -Name "powershell_ise" -ErrorAction SilentlyContinue
            Get-Process -Name "pwsh" -ErrorAction SilentlyContinue
            Get-Process -Name "OpenConsole" -ErrorAction SilentlyContinue
            Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
        )

        # Process each target
        foreach (`$process in `$targetProcesses) {
            # Check if we've already processed this ID
            if (-not `$processedIds.ContainsKey(`$process.Id)) {
                try {
                    # Set priority to Realtime
                    if (!`$process.HasExited) {
                        `$process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                        Write-Host "Set priority for `$(`$process.ProcessName) (ID: `$(`$process.Id)) to Realtime" -ForegroundColor Green

                        # Mark as processed
                        `$processedIds[`$process.Id] = `$true
                    }
                }
                catch {
                    Write-Host "Error setting priority for process `$(`$process.ProcessName) (ID: `$(`$process.Id)): `$_" -ForegroundColor Red
                }
            }
        }

        # Clean up processed IDs for processes that no longer exist
        `$runningIds = `$targetProcesses | ForEach-Object { `$_.Id }
        `$keysToRemove = @()

        foreach (`$key in `$processedIds.Keys) {
            if (`$key -notin `$runningIds) {
                `$keysToRemove += `$key
            }
        }

        foreach (`$key in `$keysToRemove) {
            `$processedIds.Remove(`$key)
        }

        # Wait before checking again
        Start-Sleep -Seconds 2
    }
}
catch {
    Write-Host "Error: `$_" -ForegroundColor Red
}
finally {
    Write-Host "Process Priority Manager stopped." -ForegroundColor Yellow
}
"@

    Set-Content -Path $OutputPath -Value $scriptContent
    Write-Host "Standalone script created at: $OutputPath" -ForegroundColor Green
}

# Function to stop Windows Update services
function Stop-WindowsUpdateServices {
    $updateServicesScript = Join-Path -Path $PSScriptRoot -ChildPath "StopWindowsUpdateServices.ps1"

    if (Test-Path $updateServicesScript) {
        Write-Host "Stopping Windows Update services..." -ForegroundColor Cyan
        & $updateServicesScript
        Write-Host "Windows Update services processing completed." -ForegroundColor Cyan
    } else {
        Write-Host "Windows Update services script not found at: $updateServicesScript" -ForegroundColor Yellow
    }
}

# Main script execution
function Main {
    # Initial run to set priority for existing processes
    Write-Host "Setting priority for existing processes..." -ForegroundColor Cyan
    Update-ProcessPriorities

    # Create standalone script
    $standaloneScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "ProcessPriorityManager_Standalone.ps1"
    Create-StandaloneScript -OutputPath $standaloneScriptPath

    # Ask if user wants to stop Windows Update services
    Write-Host "`nWould you like to stop Windows Update services?" -ForegroundColor Cyan
    Write-Host "This will stop and disable the following services:"
    Write-Host "- Windows Update"
    Write-Host "- Update Orchestrator"
    Write-Host "- Delivery Optimization"
    Write-Host "- Windows Update Medic Service"

    $stopUpdateServices = Read-Host "Stop Windows Update services? (Y/N)"

    if ($stopUpdateServices -eq "Y" -or $stopUpdateServices -eq "y") {
        Stop-WindowsUpdateServices
    }

    # Ask user how they want to run the script
    Write-Host "`nHow would you like to run the Process Priority Manager?" -ForegroundColor Cyan
    Write-Host "1. Run in current PowerShell window (Ctrl+C to stop)"
    Write-Host "2. Run as a background job (will stop when PowerShell closes)"
    Write-Host "3. Install as a scheduled task (runs at system startup)"
    Write-Host "4. Install as a Windows service (requires NSSM)"
    Write-Host "5. Exit without running"

    $choice = Read-Host "Enter your choice (1-5)"

    switch ($choice) {
        "1" {
            # Run in current window
            Write-Host "Running in current window. Press Ctrl+C to stop." -ForegroundColor Yellow

            # Keep track of processes we've already set
            $processedIds = @{}

            try {
                while ($true) {
                    # Get all target processes
                    $targetProcesses = @(
                        Get-Process -Name "powershell" -ErrorAction SilentlyContinue
                        Get-Process -Name "powershell_ise" -ErrorAction SilentlyContinue
                        Get-Process -Name "pwsh" -ErrorAction SilentlyContinue
                        Get-Process -Name "OpenConsole" -ErrorAction SilentlyContinue
                        Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
                    )

                    # Process each target
                    foreach ($process in $targetProcesses) {
                        # Check if we've already processed this ID
                        if (-not $processedIds.ContainsKey($process.Id)) {
                            Set-ProcessToRealtime -Process $process
                            # Mark as processed
                            $processedIds[$process.Id] = $true
                        }
                    }

                    # Clean up processed IDs for processes that no longer exist
                    $runningIds = $targetProcesses | ForEach-Object { $_.Id }
                    $keysToRemove = @()

                    foreach ($key in $processedIds.Keys) {
                        if ($key -notin $runningIds) {
                            $keysToRemove += $key
                        }
                    }

                    foreach ($key in $keysToRemove) {
                        $processedIds.Remove($key)
                    }

                    # Wait before checking again
                    Start-Sleep -Seconds 2
                }
            }
            catch {
                Write-Host "Error: $_" -ForegroundColor Red
            }
            finally {
                Write-Host "Process Priority Manager stopped." -ForegroundColor Yellow
            }
        }
        "2" {
            # Run as background job
            $job = Start-ProcessMonitor
            Write-Host "Background job started with ID: $($job.Id)" -ForegroundColor Green
            Write-Host "To stop the job, run: Stop-Job -Id $($job.Id); Remove-Job -Id $($job.Id)" -ForegroundColor Yellow
        }
        "3" {
            # Install as scheduled task
            Install-AsScheduledTask -ScriptPath $standaloneScriptPath
        }
        "4" {
            # Install as Windows service
            Install-AsService -ScriptPath $standaloneScriptPath
        }
        "5" {
            Write-Host "Exiting without running." -ForegroundColor Yellow
        }
        default {
            Write-Host "Invalid choice. Exiting." -ForegroundColor Red
        }
    }
}

# Run the main function
Main
