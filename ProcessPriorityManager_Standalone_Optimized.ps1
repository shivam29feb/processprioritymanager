# ProcessPriorityManager - Standalone Script (Optimized)
# This script monitors for PowerShell and OpenConsole processes and sets their priority to Realtime
# It can also stop Windows Update related services

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
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File \"$PSCommandPath\"" -Verb RunAs
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

# Function to stop Windows Update services
function Stop-WindowsUpdateServices {
    # List of Windows Update related services to stop
    $updateServices = @(
        "wuauserv",           # Windows Update
        "UsoSvc",             # Update Orchestrator Service
        "DoSvc",              # Delivery Optimization
        "WaaSMedicSvc"        # Windows Update Medic Service
    )
    
    Write-Host "=== Stopping Windows Update Services ===" -ForegroundColor Cyan
    
    foreach ($service in $updateServices) {
        try {
            $svc = Get-Service -Name $service -ErrorAction Stop
            
            # Get current status
            $currentStatus = $svc.Status
            $currentStartType = (Get-Service -Name $service).StartType
            
            Write-Host "Service: $($svc.DisplayName) ($service)" -ForegroundColor Cyan
            Write-Host "  Current Status: $currentStatus" -ForegroundColor Gray
            
            # Stop the service if it's running
            if ($currentStatus -eq "Running") {
                Write-Host "  Stopping service..." -ForegroundColor Yellow
                Stop-Service -Name $service -Force -ErrorAction Stop
                Write-Host "  Service stopped successfully." -ForegroundColor Green
            }
            else {
                Write-Host "  Service is already stopped." -ForegroundColor Green
            }
            
            # Set service to disabled
            if ($currentStartType -ne "Disabled") {
                Write-Host "  Setting service to disabled..." -ForegroundColor Yellow
                Set-Service -Name $service -StartupType Disabled -ErrorAction Stop
                Write-Host "  Service set to disabled." -ForegroundColor Green
            }
            else {
                Write-Host "  Service is already disabled." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  Error processing service $service: $_" -ForegroundColor Red
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

$stopUpdateServices = Read-Host "Stop Windows Update services? (Y/N)"

if ($stopUpdateServices -eq "Y" -or $stopUpdateServices -eq "y") {
    Stop-WindowsUpdateServices
}

# Keep track of processes we've already set
$processedIds = @{}

Write-Host "Process Priority Manager started. Monitoring for PowerShell and OpenConsole processes..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop the script." -ForegroundColor Yellow

# Create a single WMI event query for process creation
$query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_Process' AND (TargetInstance.Name = 'powershell.exe' OR TargetInstance.Name = 'powershell_ise.exe' OR TargetInstance.Name = 'pwsh.exe' OR TargetInstance.Name = 'OpenConsole.exe' OR TargetInstance.Name = 'WindowsTerminal.exe')"

# Register for process creation events
$processWatcher = New-Object System.Management.ManagementEventWatcher($query)
$processWatcher.Options.Timeout = [TimeSpan]::FromSeconds(1)

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
