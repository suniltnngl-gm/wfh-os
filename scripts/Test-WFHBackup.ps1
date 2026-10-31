<#
.DESCRIPTION
    Checks File History service/target health, recent activity, redundant project
    exclusions, and optional per-file SHA-256 backup copies.

.EXAMPLE
    .\Test-WFHBackup.ps1 -Paths @("$HOME\Projects\wfh-os\AGENTS.md")
#>

[CmdletBinding()]
param(
    [string]$ProjectsRoot = "$HOME\Projects",
    [string[]]$Paths = @(),
    [ValidateRange(1, 168)]
    [int]$MaxActivityAgeMinutes = 20,
    [switch]$SkipActivityCheck
)

$ErrorActionPreference = "Stop"
$failures = [System.Collections.Generic.List[string]]::new()

function Write-Check {
    param(
        [Parameter(Mandatory)]
        [bool]$Passed,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Passed) {
        Write-Host "[PASS] $Message"
    } else {
        Write-Host "[FAIL] $Message"
        $script:failures.Add($Message)
    }
}

function Get-BackupPath {
    param([Parameter(Mandatory)][string]$SourcePath)

    $volume = Get-Volume -FileSystemLabel "WFH" -ErrorAction Stop
    if (@($volume).Count -ne 1 -or -not $volume.DriveLetter) {
        throw "Expected one mounted File History volume labeled WFH."
    }

    $sourceFullPath = [System.IO.Path]::GetFullPath($SourcePath)
    $systemRoot = [System.IO.Path]::GetPathRoot($sourceFullPath)
    $drive = $systemRoot.TrimEnd(':\')
    $relative = $sourceFullPath.Substring($systemRoot.Length).TrimStart('\')
    return Join-Path "$($volume.DriveLetter):\FileHistory\$env:USERNAME\$env:COMPUTERNAME\Data" (
        Join-Path $drive $relative
    )
}

function Get-FileHistoryCopies {
    param([Parameter(Mandatory)][string]$SourcePath)

    $backupPath = Get-BackupPath -SourcePath $SourcePath
    $directory = Split-Path -Parent $backupPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        return @()
    }

    $fileName = [System.IO.Path]::GetFileName($backupPath)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $extension = [System.IO.Path]::GetExtension($fileName)
    $versionPattern = '^' + [regex]::Escape($stem) + ' \(.+\)' + [regex]::Escape($extension) + '$'

    return @(
        Get-ChildItem -LiteralPath $directory -File |
            Where-Object { $_.Name -eq $fileName -or $_.Name -match $versionPattern }
    )
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace("-", "")
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

$ProjectsRoot = (Resolve-Path -LiteralPath $ProjectsRoot).Path.TrimEnd('\')
$service = Get-Service -Name fhsvc -ErrorAction SilentlyContinue
Write-Check -Passed ($null -ne $service -and $service.Status -eq "Running") `
    -Message "File History service is running."

try {
    $volume = Get-Volume -FileSystemLabel "WFH" -ErrorAction Stop
    $volumeHealthy = @($volume).Count -eq 1 -and
        $volume.DriveLetter -and
        $volume.HealthStatus -eq "Healthy" -and
        $volume.OperationalStatus -contains "OK"
    Write-Check -Passed $volumeHealthy -Message "WFH target volume is mounted and healthy."
} catch {
    Write-Check -Passed $false -Message "Could not verify WFH target volume: $($_.Exception.Message)"
}

if (-not $SkipActivityCheck) {
    try {
        $activity = Get-WinEvent -FilterHashtable @{
            LogName = "Microsoft-Windows-FileHistory-Core/WHC"
            Id = 100
            StartTime = (Get-Date).AddMinutes(-$MaxActivityAgeMinutes)
        } -MaxEvents 1 -ErrorAction Stop
        Write-Check -Passed ($null -ne $activity) `
            -Message "File History reported an operational state change within $MaxActivityAgeMinutes minutes."
    } catch {
        Write-Check -Passed $false `
            -Message "No recent File History operational event was found: $($_.Exception.Message)"
    }
}

$configFile = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\FileHistory\Configuration\Config1.xml"
if (Test-Path -LiteralPath $configFile -PathType Leaf) {
    [xml]$config = Get-Content -LiteralPath $configFile
    $projectExclusions = @(
        $config.SelectNodes("//FolderExclude") |
            Where-Object {
                $_.InnerText.StartsWith("$ProjectsRoot\", [StringComparison]::OrdinalIgnoreCase)
            } |
            ForEach-Object { $_.InnerText.TrimEnd('\') }
    )
    $exclusions = @($projectExclusions | Sort-Object -Unique)
    $hasDuplicates = $projectExclusions.Count -ne $exclusions.Count

    $redundant = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $exclusions) {
        foreach ($parent in $exclusions) {
            if ($candidate.Length -gt $parent.Length -and
                $candidate.StartsWith("$parent\", [StringComparison]::OrdinalIgnoreCase)) {
                $redundant.Add($candidate)
                break
            }
        }
    }
    Write-Check -Passed (-not $hasDuplicates -and $redundant.Count -eq 0) `
        -Message "Project exclusions contain no duplicate or nested redundant rules."
} else {
    Write-Check -Passed $false -Message "File History Config1.xml was not found."
}

foreach ($path in $Paths) {
    try {
        $fullPath = [System.IO.Path]::GetFullPath($path)
        $copies = @(Get-FileHistoryCopies -SourcePath $fullPath)
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $expectedHash = Get-FileSha256 -Path $fullPath
            $matchingCopy = $copies | Where-Object {
                (Get-FileSha256 -Path $_.FullName) -eq $expectedHash
            } | Select-Object -First 1
            Write-Check -Passed ($null -ne $matchingCopy) `
                -Message "Current file content is backed up: $fullPath"
        } else {
            Write-Check -Passed ($copies.Count -gt 0) `
                -Message "A File History version exists for deleted file: $fullPath"
        }
    } catch {
        Write-Check -Passed $false -Message "Could not verify backup for '$path': $($_.Exception.Message)"
    }
}

if ($failures.Count -gt 0) {
    Write-Error "$($failures.Count) File History check(s) failed."
    exit 1
}

Write-Host "All requested File History checks passed."
exit 0
