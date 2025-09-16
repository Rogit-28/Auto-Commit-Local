<#
.SYNOPSIS
    Registers the auto-commit daemon as a Windows Task Scheduler job.

.DESCRIPTION
    Creates a scheduled task that launches auto-commit.ps1 on user login
    and runs in the background. Can also be configured to run at a specific
    interval or on system startup.

.PARAMETER Action
    install   - Registers the scheduled task
    uninstall - Removes the scheduled task
    status    - Shows current task status

.EXAMPLE
    .\setup-scheduler.ps1 -Action install
    .\setup-scheduler.ps1 -Action uninstall
    .\setup-scheduler.ps1 -Action status

.NOTES
    Must be run with Administrator privileges for task registration.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("install", "uninstall", "status")]
    [string]$Action
)

$TaskName = "AutoCommitDaemon"
$ScriptPath = Join-Path $PSScriptRoot "auto-commit.ps1"

function Install-ScheduledTask {
    Write-Host "Registering scheduled task: $TaskName" -ForegroundColor Cyan

    # Verify the script exists
    if (-not (Test-Path $ScriptPath)) {
        Write-Host "Error: auto-commit.ps1 not found at $ScriptPath" -ForegroundColor Red
        return
    }

    # Check for existing task
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Task '$TaskName' already exists. Removing old task first..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    # Create the task action
    $taskAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`"" `
        -WorkingDirectory $PSScriptRoot

    # Trigger on user logon
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn

    # Task settings
    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Days 365)

    # Register the task
    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $taskAction `
            -Trigger $taskTrigger `
            -Settings $taskSettings `
            -Description "Automatically commits and pushes Git changes at regular intervals." `
            -RunLevel Limited

        Write-Host "Task '$TaskName' registered successfully!" -ForegroundColor Green
        Write-Host "The daemon will start automatically on next login." -ForegroundColor Green
        Write-Host ""
        Write-Host "To start immediately: Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Failed to register task: $_" -ForegroundColor Red
        Write-Host "Try running this script as Administrator." -ForegroundColor Yellow
    }
}

function Uninstall-ScheduledTask {
    Write-Host "Removing scheduled task: $TaskName" -ForegroundColor Cyan

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        # Stop the task if running
        if ($existing.State -eq "Running") {
            Stop-ScheduledTask -TaskName $TaskName
            Write-Host "Stopped running task." -ForegroundColor Yellow
        }

        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Task '$TaskName' removed successfully." -ForegroundColor Green
    }
    else {
        Write-Host "Task '$TaskName' not found — nothing to remove." -ForegroundColor Yellow
    }
}

function Get-TaskStatus {
    Write-Host "Checking task status: $TaskName" -ForegroundColor Cyan
    Write-Host ""

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName
        Write-Host "  Task Name:    $TaskName" -ForegroundColor White
        Write-Host "  State:        $($existing.State)" -ForegroundColor White
        Write-Host "  Last Run:     $($info.LastRunTime)" -ForegroundColor White
        Write-Host "  Last Result:  $($info.LastTaskResult)" -ForegroundColor White
        Write-Host "  Next Run:     $($info.NextRunTime)" -ForegroundColor White
    }
    else {
        Write-Host "  Task '$TaskName' is not registered." -ForegroundColor Yellow
        Write-Host "  Run '.\setup-scheduler.ps1 -Action install' to set it up." -ForegroundColor Cyan
    }
}

# Execute the requested action
switch ($Action) {
    "install"   { Install-ScheduledTask }
    "uninstall" { Uninstall-ScheduledTask }
    "status"    { Get-TaskStatus }
}
