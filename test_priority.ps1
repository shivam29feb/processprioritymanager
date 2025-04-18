# Test script to check priority class values
$outputFile = Join-Path -Path $PSScriptRoot -ChildPath "priority_test_results.txt"

# Write to both console and file
function Write-Output-Both {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $outputFile -Value $Message
}

Write-Output-Both "RealTime value: $([int][System.Diagnostics.ProcessPriorityClass]::RealTime)"
Write-Output-Both "High value: $([int][System.Diagnostics.ProcessPriorityClass]::High)"

# Try to set current process to RealTime
$p = Get-Process -Id $PID
Write-Output-Both "Current priority: $($p.PriorityClass)"

try {
    Write-Output-Both "Attempting to set to RealTime..."
    $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
    Write-Output-Both "New priority: $($p.PriorityClass)"
} catch {
    Write-Output-Both "Error setting to RealTime: $($_.Exception.Message)"

    # Try setting to High instead
    try {
        Write-Output-Both "Attempting to set to High..."
        $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
        Write-Output-Both "New priority: $($p.PriorityClass)"
    } catch {
        Write-Output-Both "Error setting to High: $($_.Exception.Message)"
    }
}
