<#
.DESCRIPTION
    Creates a Windows Task Scheduler task that runs Update-WFHExclusions.ps1
    -AutoCommit weekly. The task also runs Test-WFHBackup.ps1 afterward to verify
    the backup succeeded, and logs results to logs\backup-history.log.

    Run this script once to set up the schedule:
        .\Schedule-WFHBackup.ps1

    To remove the task:
        .\Schedule-WFHBackup.ps1 -Remove
#>

param(
    [Switch]$Remove
)

$taskName = "DeltaOps-WFHBackup"
$scriptPath = (Resolve-Path $PSScriptRoot).Path
$exclusionsScript = Join-Path $scriptPath "Update-WFHExclusions.ps1"
$verifyScript = Join-Path $scriptPath "Test-WFHBackup.ps1"
$loggerScript = Join-Path $scriptPath "BackupLogger.ps1"

# Task command: run exclusions + auto-commit + backup, then verify
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$exclusionsScript`" -AutoCommit"

$verifyAction = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$verifyScript`""

# Trigger: weekly on Monday at 2:00 AM
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 2:00AM

# Settings: run with highest privileges, don't wake the computer
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RunOnlyIfNetworkAvailable

if ($Remove) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "✅ Removed scheduled task: $taskName"
    exit 0
}

# Build the task: exclusions → backup → verify
$actions = @($taskAction, $verifyAction)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

try {
    Register-ScheduledTask -TaskName $taskName `
        -Action $actions `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Weekly File History backup + auto-commit + verification for delta-ops" `
        -ErrorAction Stop

    Write-Host "✅ Scheduled task created: $taskName"
    Write-Host "   Runs: Update-WFHExclusions.ps1 -AutoCommit"
    Write-Host "   Then: Test-WFHBackup.ps1"
    Write-Host "   Trigger: Weekly on Monday at 2:00 AM"
} catch {
    Write-Warning "Failed to create scheduled task: $($_.Exception.Message)"
    Write-Warning "You may need to run this script as Administrator."
}