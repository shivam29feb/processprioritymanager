# ProcessPriorityManager - Standalone Script
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
            Write-Host "  Current Start Type: $currentStartType" -ForegroundColor Gray

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

Write-Host "Process Priority Manager started. Monitoring for PowerShell and OpenConsole processes..."
Write-Host "Press Ctrl+C to stop the script."

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
                try {
                    # Set priority to Realtime
                    if (!$process.HasExited) {
                        $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                        Write-Host "Set priority for $($process.ProcessName) (ID: $($process.Id)) to Realtime" -ForegroundColor Green

                        # Mark as processed
                        $processedIds[$process.Id] = $true
                    }
                }
                catch {
                    Write-Host "Error setting priority for process $($process.ProcessName) (ID: $($process.Id)): $_" -ForegroundColor Red
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
catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
finally {
    Write-Host "Process Priority Manager stopped." -ForegroundColor Yellow
}
