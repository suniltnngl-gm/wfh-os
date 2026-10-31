<#
.DESCRIPTION
    Refreshes File History exclusions, requests a backup, and waits for a
    complete operational state cycle or exact SHA-256 copies of supplied paths.
    This script never stages, commits, or pushes Git changes.

.EXAMPLE
    .\Start-DeltaOpsBackup.ps1 -Paths @(
        "$HOME\Projects\wfh-os\AGENTS.md",
        "$HOME\Projects\wfh-os\scripts\Test-WFHBackup.ps1"
    )
#>

[CmdletBinding()]
param(
    [string[]]$Paths = @(),
    [string]$PathsFile = "",
    [string]$ProjectsRoot = "$HOME\Projects",
    [ValidateRange(1, 30)]
    [int]$TimeoutMinutes = 12,
    [switch]$SkipExclusionRefresh
)

$ErrorActionPreference = "Stop"
$scriptDirectory = $PSScriptRoot

if ($PathsFile) {
    if ($Paths.Count -gt 0) {
        throw "Use either -Paths or -PathsFile, not both."
    }
    if (-not (Test-Path -LiteralPath $PathsFile -PathType Leaf)) {
        throw "Path list file not found: $PathsFile"
    }
    $Paths = @(Get-Content -LiteralPath $PathsFile | Where-Object { $_ })
}

if (-not $SkipExclusionRefresh) {
    & (Join-Path $scriptDirectory "Update-WFHExclusions.ps1") -ProjectsRoot $ProjectsRoot
}

$backupTool = Join-Path $env:WINDIR "System32\FhManagew.exe"
if (-not (Test-Path -LiteralPath $backupTool -PathType Leaf)) {
    throw "File History command was not found: $backupTool"
}

$baselineEvent = Get-WinEvent -FilterHashtable @{
    LogName = "Microsoft-Windows-FileHistory-Core/WHC"
    Id = 100
} -MaxEvents 1 -ErrorAction SilentlyContinue
$baselineState = if ($baselineEvent -and $baselineEvent.Properties.Count -gt 0) {
    [string]$baselineEvent.Properties[0].Value
} else {
    $null
}

$startedAt = Get-Date
$backupProcess = Start-Process -FilePath $backupTool -ArgumentList "-backupnow" `
    -Wait -PassThru -NoNewWindow
if ($backupProcess.ExitCode -ne 0) {
    throw "File History backup request failed with exit code $($backupProcess.ExitCode)."
}

Write-Host "File History backup requested at $($startedAt.ToString('s'))."
$deadline = $startedAt.AddMinutes($TimeoutMinutes)
$verifyScript = Join-Path $scriptDirectory "Test-WFHBackup.ps1"
$lastVerificationOutput = @()

do {
    if ($Paths.Count -gt 0) {
        $allPathsVerified = $true
        foreach ($path in $Paths) {
            $savedErrorActionPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = "Continue"
                $lastVerificationOutput = @(
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScript `
                        -ProjectsRoot $ProjectsRoot -Paths $path -SkipActivityCheck 2>&1
                )
                $verificationExitCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $savedErrorActionPreference
            }
            if ($verificationExitCode -ne 0) {
                $allPathsVerified = $false
                break
            }
        }
        if ($allPathsVerified) {
            $lastVerificationOutput | ForEach-Object { Write-Host $_ }
            Write-Host "Every requested file has a matching File History version."
            exit 0
        }
    } else {
        $events = @(
            Get-WinEvent -FilterHashtable @{
                LogName = "Microsoft-Windows-FileHistory-Core/WHC"
                Id = 100
                StartTime = $startedAt
            } -MaxEvents 50 -ErrorAction SilentlyContinue |
                Sort-Object RecordId
        )
        $leftBaselineState = $false
        $returnedToBaseline = $false
        $initialState = $null
        $sawDifferentState = $false
        $completedEvent = $null
        foreach ($event in $events) {
            if ($event.Properties.Count -eq 0) {
                continue
            }

            $state = [string]$event.Properties[0].Value
            if ($null -eq $baselineState) {
                if ($null -eq $initialState) {
                    $initialState = $state
                } elseif ($state -ne $initialState) {
                    $sawDifferentState = $true
                } elseif ($sawDifferentState) {
                    $returnedToBaseline = $true
                    $completedEvent = $event
                    break
                }
            } elseif ($state -ne $baselineState) {
                $leftBaselineState = $true
            } elseif ($leftBaselineState) {
                $returnedToBaseline = $true
                $completedEvent = $event
                break
            }
        }

        if ($returnedToBaseline) {
            Write-Host "File History completed an operational state cycle at $($completedEvent.TimeCreated.ToString('s'))."
            Write-Warning "No paths were supplied; per-file protection was not verified."
            exit 0
        }
    }

    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $deadline)

if ($Paths.Count -gt 0) {
    $lastVerificationOutput | ForEach-Object { Write-Host $_ }
    throw "Timed out after $TimeoutMinutes minutes waiting for exact File History copies of all requested files."
}

throw "Timed out after $TimeoutMinutes minutes waiting for a File History operational event."
