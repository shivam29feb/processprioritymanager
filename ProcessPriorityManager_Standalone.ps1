# ProcessPriorityManager - Standalone Script
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
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File \"$PSCommandPath\"" -Verb RunAs
    exit
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
