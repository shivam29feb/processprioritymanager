# StopWindowsUpdateServices.ps1
# This script stops Windows Update related services
# Requires administrator privileges

# Check if running as administrator
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not running as administrator, restart with elevated privileges
if (-not (Test-Administrator)) {
    Write-Host "This script requires administrator privileges to stop Windows services." -ForegroundColor Yellow
    Write-Host "Restarting with elevated privileges..." -ForegroundColor Yellow
    
    # Restart the script with elevated privileges
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# List of Windows Update related services to stop
$updateServices = @(
    "wuauserv",           # Windows Update
    "UsoSvc",             # Update Orchestrator Service
    "DoSvc",              # Delivery Optimization
    "WaaSMedicSvc"        # Windows Update Medic Service
)

# Function to stop a service and set it to disabled
function Stop-AndDisableService {
    param (
        [string]$ServiceName
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        
        # Get current status
        $currentStatus = $service.Status
        $currentStartType = (Get-Service -Name $ServiceName).StartType
        
        Write-Host "Service: $($service.DisplayName) ($ServiceName)" -ForegroundColor Cyan
        Write-Host "  Current Status: $currentStatus" -ForegroundColor Gray
        Write-Host "  Current Start Type: $currentStartType" -ForegroundColor Gray
        
        # Stop the service if it's running
        if ($currentStatus -eq "Running") {
            Write-Host "  Stopping service..." -ForegroundColor Yellow
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Write-Host "  Service stopped successfully." -ForegroundColor Green
        }
        else {
            Write-Host "  Service is already stopped." -ForegroundColor Green
        }
        
        # Set service to disabled
        if ($currentStartType -ne "Disabled") {
            Write-Host "  Setting service to disabled..." -ForegroundColor Yellow
            Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop
            Write-Host "  Service set to disabled." -ForegroundColor Green
        }
        else {
            Write-Host "  Service is already disabled." -ForegroundColor Green
        }
        
        return $true
    }
    catch {
        Write-Host "  Error processing service $ServiceName`: $_" -ForegroundColor Red
        return $false
    }
}

# Main function to stop all Windows Update services
function Stop-WindowsUpdateServices {
    Write-Host "=== Stopping Windows Update Services ===" -ForegroundColor Cyan
    
    $allSuccessful = $true
    
    foreach ($service in $updateServices) {
        $result = Stop-AndDisableService -ServiceName $service
        if (-not $result) {
            $allSuccessful = $false
        }
        Write-Host ""
    }
    
    if ($allSuccessful) {
        Write-Host "All Windows Update services have been stopped and disabled successfully." -ForegroundColor Green
    }
    else {
        Write-Host "Some services could not be stopped or disabled. Check the log above for details." -ForegroundColor Yellow
    }
    
    return $allSuccessful
}

# Run the main function
Stop-WindowsUpdateServices

# If running standalone, wait for user input before closing
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
