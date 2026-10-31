<#
.DESCRIPTION
    Verifies the Windows File History service and its native scheduled activity.
    File History already manages its own backup interval; this script does not
    create a second timer or make Git commits.

.EXAMPLE
    .\Schedule-WFHBackup.ps1

.EXAMPLE
    .\Schedule-WFHBackup.ps1 -RemoveLegacyTask
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 168)]
    [int]$MaxActivityAgeMinutes = 25,
    [Alias("Remove")]
    [switch]$RemoveLegacyTask
)

$ErrorActionPreference = "Stop"
$legacyTaskName = "DeltaOps-WFHBackup"

if ($RemoveLegacyTask) {
    $legacyTask = Get-ScheduledTask -TaskName $legacyTaskName -ErrorAction SilentlyContinue
    if ($legacyTask) {
        Unregister-ScheduledTask -TaskName $legacyTaskName -Confirm:$false -ErrorAction Stop
        Write-Host "Removed legacy duplicate task '$legacyTaskName'."
    } else {
        Write-Host "No legacy duplicate task is registered."
    }
    exit 0
}

$service = Get-Service -Name fhsvc -ErrorAction Stop
if ($service.Status -ne "Running") {
    throw "File History service is $($service.Status); expected Running."
}

$target = Get-Volume -FileSystemLabel "WFH" -ErrorAction Stop
if (@($target).Count -ne 1 -or -not $target.DriveLetter -or
    $target.HealthStatus -ne "Healthy" -or $target.OperationalStatus -notcontains "OK") {
    throw "The WFH File History target is not mounted and healthy."
}

$latestEvent = Get-WinEvent -FilterHashtable @{
    LogName = "Microsoft-Windows-FileHistory-Core/WHC"
    Id = 100
    StartTime = (Get-Date).AddMinutes(-$MaxActivityAgeMinutes)
} -MaxEvents 1 -ErrorAction SilentlyContinue
if ($null -eq $latestEvent) {
    throw "No File History operational event was recorded in the last $MaxActivityAgeMinutes minutes."
}

Write-Host "File History is running and recently reported an operational state change."
Write-Host "Target: $($target.DriveLetter):\ ($($target.FileSystemLabel))"
Write-Host "Last state event: $($latestEvent.TimeCreated.ToString('s'))"
Write-Host "No duplicate scheduled task was created; Windows File History controls its own interval."
