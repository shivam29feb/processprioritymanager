# SetWindsurfPriority.ps1
# This script monitors for 'windsurf' processes and sets their priority to Realtime.

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
    try {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to restart with elevated privileges: $_" -ForegroundColor Red
        Write-Host "Please run this script as an Administrator." -ForegroundColor Red
        pause
    }
    exit
}

# Function to set process priority to Realtime
function Set-ProcessToRealtime {
    param (
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$ProcessObject
    )

    try {
        # Check if the process is still running
        if ($ProcessObject -and (-not $ProcessObject.HasExited)) {
            # Get the current priority
            $currentPriority = $ProcessObject.PriorityClass

            # Only change if not already set to Realtime
            if ($currentPriority -ne [System.Diagnostics.ProcessPriorityClass]::RealTime) {
                Write-Host "Setting process '$($ProcessObject.ProcessName)' (ID: $($ProcessObject.Id)) priority to Realtime" -ForegroundColor Cyan
                $ProcessObject.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
                Write-Host "Successfully set priority for '$($ProcessObject.ProcessName)' (ID: $($ProcessObject.Id)) to Realtime" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "Error setting priority for process '$($ProcessObject.ProcessName)' (ID: $($ProcessObject.Id)): $_" -ForegroundColor Red
    }
}

# Main monitoring loop
function Start-WindsurfPriorityMonitor {
    Write-Host "Starting Windsurf process priority monitor..." -ForegroundColor Cyan
    Write-Host "Will set 'windsurf' processes to Realtime priority."
    Write-Host "Press CTRL+C to stop the monitor."

    $processedIds = @{}

    while ($true) {
        try {
            $windsurfProcesses = Get-Process -Name "windsurf" -ErrorAction SilentlyContinue

            foreach ($process in $windsurfProcesses) {
                if ($process -and (-not $process.HasExited)) {
                    if (-not $processedIds.ContainsKey($process.Id)) {
                        Set-ProcessToRealtime -ProcessObject $process
                        if ($process.PriorityClass -eq [System.Diagnostics.ProcessPriorityClass]::RealTime) {
                            $processedIds[$process.Id] = $true # Mark as processed if successfully set
                        }
                    } elseif (($processedIds.ContainsKey($process.Id)) -and ($process.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::RealTime)) {
                        # If it was processed but priority changed, set it again
                        Write-Host "Re-setting priority for already processed '$($process.ProcessName)' (ID: $($process.Id)) as it's not Realtime." -ForegroundColor Yellow
                        Set-ProcessToRealtime -ProcessObject $process
                         if ($process.PriorityClass -eq [System.Diagnostics.ProcessPriorityClass]::RealTime) {
                            $processedIds[$process.Id] = $true 
                        }
                    }
                }
            }

            # Clean up processed IDs for processes that no longer exist
            $currentRunningIds = $windsurfProcesses | Where-Object {$PSItem -ne $null} | ForEach-Object { $_.Id }
            $keysToRemove = $processedIds.Keys | Where-Object { $_ -notin $currentRunningIds }

            foreach ($key in $keysToRemove) {
                $processedIds.Remove($key)
                Write-Host "Removed process ID $key from processed list as it is no longer running." -ForegroundColor Magenta
            }
        }
        catch {
            Write-Host "An error occurred in the monitoring loop: $_" -ForegroundColor Red
        }
        
        # Wait before checking again
        Start-Sleep -Seconds 5
    }
}

# --- Main Script Execution ---
Write-Host "Windsurf Process Priority Manager" -ForegroundColor White
Write-Host "---------------------------------" -ForegroundColor White

# Start the monitor
Start-WindsurfPriorityMonitor
