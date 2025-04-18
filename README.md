# Process Priority Manager

This tool automatically sets the priority of PowerShell and OpenConsole processes to "Realtime" whenever they start. It continuously monitors for new processes and adjusts their priority in the background.

> **Note:** Administrator privileges are required to set process priority to "Realtime". The application will automatically request elevated privileges when needed.

## Features

- Monitors for PowerShell, PowerShell ISE, PowerShell Core, OpenConsole, and Windows Terminal processes
- Sets process priority to "Realtime" for better performance
- Multiple deployment options:
  - Run in a PowerShell window
  - Run as a background job
  - Install as a scheduled task (runs at system startup)
  - Install as a Windows service (requires NSSM)
- Automatically cleans up tracking for processes that have ended

## Requirements

- Windows operating system
- PowerShell 5.1 or later
- Administrator privileges (for setting process priorities)
- NSSM (Non-Sucking Service Manager) - only if installing as a service

## Usage

### Option 1: Using the Batch File

1. Double-click the `RunProcessPriorityManager.bat` file
2. Follow the on-screen prompts to choose how you want to run the tool

### Option 2: Running the PowerShell Script Directly

1. Right-click on `ProcessPriorityManager.ps1` and select "Run with PowerShell"
2. If prompted about execution policy, select "Yes" to allow the script to run
3. Follow the on-screen prompts to choose how you want to run the tool

## Deployment Options

### 1. Run in Current PowerShell Window

- The script will run in the current window and show real-time output
- Press Ctrl+C to stop the script
- The script will stop when you close the PowerShell window

### 2. Run as a Background Job

- The script will run in the background within PowerShell
- You can continue to use PowerShell for other tasks
- The job will stop when you close PowerShell
- To stop the job manually, use the commands shown after starting the job

### 3. Install as a Scheduled Task

- Creates a Windows scheduled task that runs at system startup
- Runs with SYSTEM privileges to ensure it can modify process priorities
- The task will continue to run even after you log off
- You can manage the task in Task Scheduler

### 4. Install as a Windows Service

- Requires NSSM (Non-Sucking Service Manager)
- Creates a Windows service that runs automatically at system startup
- Runs with SYSTEM privileges to ensure it can modify process priorities
- The service will continue to run even after you log off
- You can manage the service in Services.msc

## Standalone Script

The tool also creates a standalone script called `ProcessPriorityManager_Standalone.ps1` that can be used independently. This script contains all the necessary code to monitor and set process priorities without any user interaction.

## Troubleshooting

- If you encounter "Access Denied" errors, make sure you're running PowerShell as Administrator
- If the script doesn't detect processes, try restarting it
- If installing as a service fails, make sure NSSM is installed and accessible

## Notes

- Setting processes to "Realtime" priority can potentially cause system instability if the process uses too much CPU
- This tool is intended for use on systems where PowerShell/console performance is critical
- Use at your own risk on production systems
