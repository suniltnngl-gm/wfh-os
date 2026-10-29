<#
.DESCRIPTION
    Simple structured logging for File History operations.
    Writes timestamped entries to:
        logs\backup-history.log

.EXAMPLE
    # In Update-WFHExclusions.ps1 at a key point:
    .\BackupLogger.ps1 -Action "exclusions" -Message "refreshed" -Count 12
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("exclusions", "backup", "autocommit", "verification", "error")]
    [string]$Action,

    [Parameter()]
    [string]$Message = "",

    [Parameter()]
    [int]$Count = 0
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$logDir = Join-Path $scriptDir ".." "logs"
$logDir = Resolve-Path $logDir -ErrorAction SilentlyContinue
if (-not $logDir) {
    $logDir = Join-Path $scriptDir ".." "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
} else {
    $logDir = $logDir.Path
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$entry = [PSCustomObject]@{
    Timestamp  = $timestamp
    Action     = $Action
    Message    = $Message
    Count      = $Count
}

Write-Host "$($entry.Timestamp)"
Write-Host "  $($entry.Action): $($entry.Message)"
if ($Count -gt 0) { Write-Host "  - $Count entries" }
Write-Host ""

$logFile = Join-Path $logDir "backup-history.log"
Add-Content -Path $logFile -Value ""
$line = "$($entry.Timestamp)`n  $($entry.Action): $($entry.Message)"
if ($Count -gt 0) {
    $line += "`n- $Count entries"
}
Add-Content -Path $logFile -Value $line