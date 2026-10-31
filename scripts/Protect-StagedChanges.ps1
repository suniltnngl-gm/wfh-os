<#
.DESCRIPTION
    Verifies staged contents and requires external pre-edit snapshots for
    modified, deleted, and renamed existing files.
#>

[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$BackupRoot = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PreEditSnapshot.Common.ps1")

if (-not $BackupRoot) {
    $BackupRoot = Get-DefaultBackupRoot
}
$RepositoryRoot = Get-RepositoryRoot -RepositoryRoot $RepositoryRoot
$BackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)

$stagedChanges = @(& git -C $RepositoryRoot diff --cached --name-status --diff-filter=ACDMRTUXB)
if ($LASTEXITCODE -ne 0) {
    throw "Could not read staged Git changes."
}
if ($stagedChanges | Where-Object { $_ -match "[`r`n]" }) {
    throw "Staged paths containing newlines are not supported by this hook."
}
if ($stagedChanges.Count -eq 0) {
    Write-Host "No staged files; snapshot check is not needed."
    exit 0
}

$snapshotRequired = [System.Collections.Generic.List[string]]::new()
foreach ($change in $stagedChanges) {
    $parts = $change -split "`t"
    $status = $parts[0]
    if ($status -match '^R[0-9]+$') {
        if ($parts.Count -ne 3) {
            throw "Could not parse staged rename: $change"
        }
        $snapshotRequired.Add($parts[1])
    } elseif ($status -in @("M", "D", "T")) {
        if ($parts.Count -ne 2) {
            throw "Could not parse staged change: $change"
        }
        $snapshotRequired.Add($parts[1])
    }
}

foreach ($change in $stagedChanges) {
    $parts = $change -split "`t"
    $paths = if ($parts[0] -match '^R[0-9]+$') { @($parts[1], $parts[2]) } else { @($parts[1]) }
    foreach ($stagedPath in $paths) {
        if ($stagedPath.Contains("`t")) {
            throw "Staged paths containing tabs are not supported by this hook."
        }
        $workingTreeDiff = & git -C $RepositoryRoot diff --quiet -- $stagedPath
        if ($LASTEXITCODE -eq 1) {
            throw "Working-tree content differs from the index for '$stagedPath'. Stage the final content, then retry."
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Could not compare the working tree with the index for '$stagedPath'."
        }
    }
}

foreach ($relativePath in $snapshotRequired | Sort-Object -Unique) {
    $normalizedPath = ConvertTo-RepositoryRelativePath -RepositoryRoot $RepositoryRoot -Path $relativePath
    $snapshots = @(Get-SnapshotFiles -RepositoryRoot $RepositoryRoot `
        -RelativePath $normalizedPath -BackupRoot $BackupRoot)
    if ($snapshots.Count -eq 0) {
        throw "No pre-edit snapshot found for '$relativePath'. Run scripts\Save-PreEditSnapshot.ps1 before editing."
    }
}

Write-Host "Staged contents and external pre-edit snapshots verified; allowing commit."
exit 0
