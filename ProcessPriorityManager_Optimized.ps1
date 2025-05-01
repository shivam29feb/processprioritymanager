# ProcessPriorityManager_Optimized.ps1
# This script monitors for PowerShell and OpenConsole processes and sets their priority to Realtime
# Optimized for lower CPU usage

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

# Target process names to monitor
$targetProcessNames = @(
    "powershell",
    "powershell_ise",
    "pwsh",
    "OpenConsole",
    "WindowsTerminal"
)

# Function to set process priority to Realtime with minimal output
function Set-ProcessToRealtime {
    param (
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [switch]$Quiet
    )

    try {
        # Check if the process is still running
        if (!$Process.HasExited) {
            # Only change if not already set to Realtime
            if ($Process.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::RealTime) {
                $Process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                
                if (-not $Quiet) {
                    Write-Host "Set priority for $($Process.ProcessName) (ID: $($Process.Id)) to Realtime" -ForegroundColor Green
                }
                
                return $true
            }
        }
    }
    catch {
        if (-not $Quiet) {
            Write-Host "Error setting priority for process $($Process.ProcessName) (ID: $($Process.Id)): $_" -ForegroundColor Red
        }
    }
    
    return $false
}

# Function to find and set priority for target processes - initial run
function Update-ProcessPriorities {
    # Get all target processes in a single operation
    $processes = Get-Process | Where-Object { $targetProcessNames -contains $_.ProcessName }
    
    # Set priority for each process
    foreach ($process in $processes) {
        Set-ProcessToRealtime -Process $process
    }
}

# Function to create a background job that monitors for new processes
function Start-ProcessMonitor {
    # Create a script block for the background job with optimizations
    $monitorScript = {
        param($targetNames)
        
        # Keep track of processes we've already set
        $processedIds = @{}
        
        # Create a single WMI event query for process creation
        $query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_Process' AND (TargetInstance.Name = 'powershell.exe' OR TargetInstance.Name = 'powershell_ise.exe' OR TargetInstance.Name = 'pwsh.exe' OR TargetInstance.Name = 'OpenConsole.exe' OR TargetInstance.Name = 'WindowsTerminal.exe')"
        
        # Register for process creation events
        $processWatcher = New-Object System.Management.ManagementEventWatcher($query)
        $processWatcher.Options.Timeout = [TimeSpan]::FromSeconds(1)
        
        # Initial run to set priority for existing processes
        $processes = Get-Process | Where-Object { $targetNames -contains $_.ProcessName }
        foreach ($process in $processes) {
            try {
                if (!$process.HasExited -and -not $processedIds.ContainsKey($process.Id)) {
                    $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                    $processedIds[$process.Id] = $true
                    Write-Output "Set priority for $($process.ProcessName) (ID: $($process.Id)) to Realtime"
                }
            }
            catch {
                # Silently continue
            }
        }
        
        # Periodically check for new processes and clean up old ones
        $timer = New-Object System.Timers.Timer
        $timer.Interval = 10000  # Check every 10 seconds instead of 2
        $timer.AutoReset = $true
        
        $timerAction = {
            # Clean up processed IDs for processes that no longer exist
            $runningProcesses = Get-Process -ErrorAction SilentlyContinue
            $runningIds = $runningProcesses | ForEach-Object { $_.Id }
            
            $keysToRemove = $processedIds.Keys | Where-Object { $_ -notin $runningIds }
            foreach ($key in $keysToRemove) {
                $processedIds.Remove($key)
            }
            
            # Check for any missed processes
            $processes = $runningProcesses | Where-Object { $targetNames -contains $_.ProcessName }
            foreach ($process in $processes) {
                try {
                    if (!$process.HasExited -and -not $processedIds.ContainsKey($process.Id)) {
                        $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                        $processedIds[$process.Id] = $true
                        Write-Output "Set priority for $($process.ProcessName) (ID: $($process.Id)) to Realtime"
                    }
                }
                catch {
                    # Silently continue
                }
            }
        }
        
        $timer.Elapsed.Add($timerAction)
        $timer.Start()
        
        try {
            # Main event loop
            while ($true) {
                try {
                    $processEvent = $processWatcher.WaitForNextEvent()
                    $process = [System.Diagnostics.Process]::GetProcessById($processEvent.TargetInstance.ProcessId)
                    
                    if (-not $processedIds.ContainsKey($process.Id)) {
                        try {
                            if (!$process.HasExited) {
                                $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                                $processedIds[$process.Id] = $true
                                Write-Output "Set priority for $($process.ProcessName) (ID: $($process.Id)) to Realtime"
                            }
                        }
                        catch {
                            # Silently continue
                        }
                    }
                }
                catch [System.Management.ManagementException] {
                    # Timeout, just continue
                }
                catch {
                    Write-Output "Error in event processing: $_"
                }
            }
        }
        finally {
            $processWatcher.Stop()
            $timer.Stop()
            $timer.Dispose()
        }
    }
    
    # Start the background job with the target process names
    $job = Start-Job -ScriptBlock $monitorScript -ArgumentList (,$targetProcessNames)
    return $job
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

# Create a standalone script that can be run directly
function Create-StandaloneScript {
    param (
        [string]$OutputPath
    )

    $scriptContent = @"
# ProcessPriorityManager - Standalone Script (Optimized)
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

# Target process names to monitor
`$targetProcessNames = @(
    "powershell",
    "powershell_ise",
    "pwsh",
    "OpenConsole",
    "WindowsTerminal"
)

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

Write-Host "Process Priority Manager started. Monitoring for PowerShell and OpenConsole processes..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop the script." -ForegroundColor Yellow

# Create a single WMI event query for process creation
`$query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_Process' AND (TargetInstance.Name = 'powershell.exe' OR TargetInstance.Name = 'powershell_ise.exe' OR TargetInstance.Name = 'pwsh.exe' OR TargetInstance.Name = 'OpenConsole.exe' OR TargetInstance.Name = 'WindowsTerminal.exe')"

# Register for process creation events
`$processWatcher = New-Object System.Management.ManagementEventWatcher(`$query)
`$processWatcher.Options.Timeout = [TimeSpan]::FromSeconds(1)

# Initial run to set priority for existing processes
`$processes = Get-Process | Where-Object { `$targetProcessNames -contains `$_.ProcessName }
foreach (`$process in `$processes) {
    try {
        if (!`$process.HasExited -and -not `$processedIds.ContainsKey(`$process.Id)) {
            `$process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
            `$processedIds[`$process.Id] = `$true
            Write-Host "Set priority for `$(`$process.ProcessName) (ID: `$(`$process.Id)) to Realtime" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error setting priority: `$_" -ForegroundColor Red
    }
}

# Create a timer for cleanup
`$timer = New-Object System.Timers.Timer
`$timer.Interval = 10000  # Check every 10 seconds
`$timer.AutoReset = `$true

`$timerAction = {
    # Clean up processed IDs for processes that no longer exist
    `$runningProcesses = Get-Process -ErrorAction SilentlyContinue
    `$runningIds = `$runningProcesses | ForEach-Object { `$_.Id }
    
    `$keysToRemove = `$processedIds.Keys | Where-Object { `$_ -notin `$runningIds }
    foreach (`$key in `$keysToRemove) {
        `$processedIds.Remove(`$key)
    }
    
    # Check for any missed processes
    `$processes = `$runningProcesses | Where-Object { `$targetProcessNames -contains `$_.ProcessName }
    foreach (`$process in `$processes) {
        try {
            if (!`$process.HasExited -and -not `$processedIds.ContainsKey(`$process.Id)) {
                `$process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                `$processedIds[`$process.Id] = `$true
                Write-Host "Set priority for `$(`$process.ProcessName) (ID: `$(`$process.Id)) to Realtime" -ForegroundColor Green
            }
        }
        catch {
            # Silently continue
        }
    }
}

`$timer.Elapsed.Add(`$timerAction)
`$timer.Start()

try {
    # Main event loop
    while (`$true) {
        try {
            `$processEvent = `$processWatcher.WaitForNextEvent()
            `$processId = `$processEvent.TargetInstance.ProcessId
            
            try {
                `$process = [System.Diagnostics.Process]::GetProcessById(`$processId)
                
                if (-not `$processedIds.ContainsKey(`$process.Id)) {
                    if (!`$process.HasExited) {
                        `$process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                        `$processedIds[`$process.Id] = `$true
                        Write-Host "Set priority for `$(`$process.ProcessName) (ID: `$(`$process.Id)) to Realtime" -ForegroundColor Green
                    }
                }
            }
            catch {
                # Process might have exited already, just continue
            }
        }
        catch [System.Management.ManagementException] {
            # Timeout, just continue
            Start-Sleep -Milliseconds 100  # Add a small sleep to reduce CPU usage
        }
        catch {
            Write-Host "Error in event processing: `$_" -ForegroundColor Red
            Start-Sleep -Seconds 1  # Sleep on error to prevent tight error loops
        }
    }
}
catch {
    Write-Host "Error: `$_" -ForegroundColor Red
}
finally {
    `$processWatcher.Stop()
    `$timer.Stop()
    `$timer.Dispose()
    Write-Host "Process Priority Manager stopped." -ForegroundColor Yellow
}
"@

    Set-Content -Path $OutputPath -Value $scriptContent
    Write-Host "Optimized standalone script created at: $OutputPath" -ForegroundColor Green
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

# Main script execution
function Main {
    # Initial run to set priority for existing processes
    Write-Host "Setting priority for existing processes..." -ForegroundColor Cyan
    Update-ProcessPriorities

    # Create standalone script
    $standaloneScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "ProcessPriorityManager_Standalone_Optimized.ps1"
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
            
            # Create a single WMI event query for process creation
            $query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_Process' AND (TargetInstance.Name = 'powershell.exe' OR TargetInstance.Name = 'powershell_ise.exe' OR TargetInstance.Name = 'pwsh.exe' OR TargetInstance.Name = 'OpenConsole.exe' OR TargetInstance.Name = 'WindowsTerminal.exe')"
            
            # Register for process creation events
            $processWatcher = New-Object System.Management.ManagementEventWatcher($query)
            $processWatcher.Options.Timeout = [TimeSpan]::FromSeconds(1)
            
            # Keep track of processes we've already set
            $processedIds = @{}
            
            # Initial run to set priority for existing processes
            $processes = Get-Process | Where-Object { $targetProcessNames -contains $_.ProcessName }
            foreach ($process in $processes) {
                try {
                    if (!$process.HasExited -and -not $processedIds.ContainsKey($process.Id)) {
                        $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                        $processedIds[$process.Id] = $true
                        Write-Host "Set priority for $($process.ProcessName) (ID: $($process.Id)) to Realtime" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Host "Error setting priority: $_" -ForegroundColor Red
                }
            }
            
            # Create a timer for cleanup
            $timer = New-Object System.Timers.Timer
            $timer.Interval = 10000  # Check every 10 seconds
            $timer.AutoReset = $true
            
            $timerAction = {
                # Clean up processed IDs for processes that no longer exist
                $runningProcesses = Get-Process -ErrorAction SilentlyContinue
                $runningIds = $runningProcesses | ForEach-Object { $_.Id }
                
                $keysToRemove = $processedIds.Keys | Where-Object { $_ -notin $runningIds }
                foreach ($key in $keysToRemove) {
                    $processedIds.Remove($key)
                }
                
                # Check for any missed processes
                $processes = $runningProcesses | Where-Object { $targetProcessNames -contains $_.ProcessName }
                foreach ($process in $processes) {
                    try {
                        if (!$process.HasExited -and -not $processedIds.ContainsKey($process.Id)) {
                            $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                            $processedIds[$process.Id] = $true
                            Write-Host "Set priority for $($process.ProcessName) (ID: $($process.Id)) to Realtime" -ForegroundColor Green
                        }
                    }
                    catch {
                        # Silently continue
                    }
                }
            }
            
            $timer.Elapsed.Add($timerAction)
            $timer.Start()
            
            try {
                # Main event loop
                while ($true) {
                    try {
                        $processEvent = $processWatcher.WaitForNextEvent()
                        $processId = $processEvent.TargetInstance.ProcessId
                        
                        try {
                            $process = [System.Diagnostics.Process]::GetProcessById($processId)
                            
                            if (-not $processedIds.ContainsKey($process.Id)) {
                                if (!$process.HasExited) {
                                    $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                                    $processedIds[$process.Id] = $true
                                    Write-Host "Set priority for $($process.ProcessName) (ID: $($process.Id)) to Realtime" -ForegroundColor Green
                                }
                            }
                        }
                        catch {
                            # Process might have exited already, just continue
                        }
                    }
                    catch [System.Management.ManagementException] {
                        # Timeout, just continue
                        Start-Sleep -Milliseconds 100  # Add a small sleep to reduce CPU usage
                    }
                    catch {
                        Write-Host "Error in event processing: $_" -ForegroundColor Red
                        Start-Sleep -Seconds 1  # Sleep on error to prevent tight error loops
                    }
                }
            }
            catch {
                Write-Host "Error: $_" -ForegroundColor Red
            }
            finally {
                $processWatcher.Stop()
                $timer.Stop()
                $timer.Dispose()
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
