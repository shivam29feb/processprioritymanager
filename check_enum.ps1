# Check ProcessPriorityClass enum values
$outputFile = Join-Path -Path $PSScriptRoot -ChildPath "enum_values.txt"

# Write all enum values
"ProcessPriorityClass Enum Values:" | Out-File -FilePath $outputFile -Encoding ASCII
[Enum]::GetValues([System.Diagnostics.ProcessPriorityClass]) | ForEach-Object {
    "$_ = $([int]$_)" | Out-File -FilePath $outputFile -Append -Encoding ASCII
}

# Write current process priority
$p = Get-Process -Id $PID
"Current process priority: $($p.PriorityClass) = $([int]$p.PriorityClass)" | Out-File -FilePath $outputFile -Append -Encoding ASCII
