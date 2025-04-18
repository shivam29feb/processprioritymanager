# Check if the script is setting the priority correctly
$outputFile = "priority_check.txt"

# Clear the file if it exists
if (Test-Path $outputFile) {
    Remove-Item $outputFile
}

# Write the enum values
"RealTime = $([int][System.Diagnostics.ProcessPriorityClass]::RealTime)" | Add-Content $outputFile
"High = $([int][System.Diagnostics.ProcessPriorityClass]::High)" | Add-Content $outputFile

# Get the current process
$p = Get-Process -Id $PID
"Current priority: $($p.PriorityClass)" | Add-Content $outputFile

# Try to set to RealTime
try {
    "Attempting to set to RealTime..." | Add-Content $outputFile
    $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
    "New priority: $($p.PriorityClass)" | Add-Content $outputFile
} catch {
    "Error setting to RealTime: $($_.Exception.Message)" | Add-Content $outputFile
}

# Now check the actual script
"Checking ProcessPriorityManager.ps1..." | Add-Content $outputFile

# Find all instances where priority is set
$scriptContent = Get-Content -Path "ProcessPriorityManager.ps1" -Raw
$matches = [regex]::Matches($scriptContent, "PriorityClass\s*=\s*\[System\.Diagnostics\.ProcessPriorityClass\]::\w+")

"Found $($matches.Count) instances of setting priority:" | Add-Content $outputFile
foreach ($match in $matches) {
    $match.Value | Add-Content $outputFile
}

# Check if any are setting to High instead of RealTime
$highMatches = [regex]::Matches($scriptContent, "PriorityClass\s*=\s*\[System\.Diagnostics\.ProcessPriorityClass\]::High")
if ($highMatches.Count -gt 0) {
    "WARNING: Found $($highMatches.Count) instances of setting priority to High instead of RealTime:" | Add-Content $outputFile
    foreach ($match in $highMatches) {
        $match.Value | Add-Content $outputFile
    }
}
