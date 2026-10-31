<#
.DESCRIPTION
    Saves exact pre-edit copies of existing repository files outside Git.

.EXAMPLE
    .\Save-PreEditSnapshot.ps1 -Paths @("AGENTS.md", "scripts\Start-DeltaOpsBackup.ps1")
#>

[CmdletBinding()]
param(
    [string[]]$Paths = @(),
    [string]$PathsFile = "",
    [string]$RepositoryRoot = "",
    [string]$BackupRoot = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PreEditSnapshot.Common.ps1")
$RepositoryRoot = Get-RepositoryRoot -RepositoryRoot $RepositoryRoot
if (-not $BackupRoot) {
    $BackupRoot = Get-DefaultBackupRoot
}
$BackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)

if ($PathsFile) {
    if ($Paths.Count -gt 0) {
        throw "Use either -Paths or -PathsFile, not both."
    }
    if (-not (Test-Path -LiteralPath $PathsFile -PathType Leaf)) {
        throw "Path list file not found: $PathsFile"
    }
    $Paths = @(Get-Content -LiteralPath $PathsFile | Where-Object { $_ })
}
if ($Paths.Count -eq 0) {
    throw "Specify one or more existing files with -Paths or -PathsFile."
}

$coverageScript = Join-Path $PSScriptRoot "Test-ProtectionCoverage.ps1"
$coveragePathsFile = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllLines(
        $coveragePathsFile,
        $Paths,
        [System.Text.Encoding]::UTF8
    )
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $coverageScript `
        -RepositoryRoot $RepositoryRoot -BackupRoot $BackupRoot `
        -PathsFile $coveragePathsFile -ShowExclusions
    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify protection coverage before creating snapshots."
    }
} finally {
    Remove-Item -LiteralPath $coveragePathsFile -Force -ErrorAction Stop
}

$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $Paths) {
    $relativePath = ConvertTo-RepositoryRelativePath -RepositoryRoot $RepositoryRoot -Path $path
    if (-not $seen.Add($relativePath)) {
        continue
    }

    $sourcePath = Join-Path $RepositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Pre-edit snapshot source does not exist: $sourcePath"
    }

    $directory = Get-SnapshotDirectory -RepositoryRoot $RepositoryRoot `
        -RelativePath $relativePath -BackupRoot $BackupRoot
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $existingSnapshots = @(Get-SnapshotFiles -RepositoryRoot $RepositoryRoot `
        -RelativePath $relativePath -BackupRoot $BackupRoot)
    $nextNumber = 1
    if ($existingSnapshots.Count -gt 0) {
        $lastName = $existingSnapshots[-1].Name
        $match = [regex]::Match($lastName, '\.bak([1-9][0-9]*)$')
        $nextNumber = [long]$match.Groups[1].Value + 1
    }

    $snapshotPath = Join-Path $directory ((Split-Path $relativePath -Leaf) + ".bak$nextNumber")
    $temporaryPath = "$snapshotPath.tmp.$([guid]::NewGuid().ToString('N'))"
    try {
        Copy-Item -LiteralPath $sourcePath -Destination $temporaryPath -ErrorAction Stop
        $sourceHash = Get-ContentSha256 -Path $sourcePath
        $snapshotHash = Get-ContentSha256 -Path $temporaryPath
        if ($sourceHash -ne $snapshotHash) {
            throw "Snapshot SHA-256 verification failed: $snapshotPath"
        }
        Move-Item -LiteralPath $temporaryPath -Destination $snapshotPath -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
        }
    }

    Write-Host "[PASS] $relativePath => $snapshotPath [$sourceHash]"
}

$verificationPathsFile = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllLines(
        $verificationPathsFile,
        $Paths,
        [System.Text.Encoding]::UTF8
    )
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $coverageScript `
        -RepositoryRoot $RepositoryRoot -BackupRoot $BackupRoot `
        -PathsFile $verificationPathsFile
    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify protection coverage after creating snapshots."
    }
} finally {
    Remove-Item -LiteralPath $verificationPathsFile -Force -ErrorAction Stop
}
