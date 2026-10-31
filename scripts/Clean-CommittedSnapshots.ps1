<#
.DESCRIPTION
    Removes external pre-edit snapshots only for paths included in a successful commit.
#>

[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$BackupRoot = "",
    [string]$Commit = "HEAD"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PreEditSnapshot.Common.ps1")
$RepositoryRoot = Get-RepositoryRoot -RepositoryRoot $RepositoryRoot
if (-not $BackupRoot) {
    $BackupRoot = Get-DefaultBackupRoot
}
$BackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)

$committedPaths = @(& git -C $RepositoryRoot diff-tree --root --no-commit-id `
    --name-only -r -m $Commit)
if ($LASTEXITCODE -ne 0) {
    throw "Could not read paths from commit '$Commit'."
}
if ($committedPaths | Where-Object { $_ -match "[`r`n]" }) {
    throw "Committed paths containing newlines are not supported."
}

foreach ($path in $committedPaths | Sort-Object -Unique) {
    $relativePath = ConvertTo-RepositoryRelativePath -RepositoryRoot $RepositoryRoot -Path $path
    $snapshots = @(Get-SnapshotFiles -RepositoryRoot $RepositoryRoot `
        -RelativePath $relativePath -BackupRoot $BackupRoot)
    foreach ($snapshot in $snapshots) {
        Remove-Item -LiteralPath $snapshot.FullName -Force -ErrorAction Stop
        Write-Host "[REMOVED] $($snapshot.FullName)"
    }

    $directory = Get-SnapshotDirectory -RepositoryRoot $RepositoryRoot `
        -RelativePath $relativePath -BackupRoot $BackupRoot
    $repositoryBackupRoot = Join-Path $BackupRoot (Split-Path $RepositoryRoot -Leaf)
    while ((Test-Path -LiteralPath $directory -PathType Container) -and
        $directory.StartsWith("$repositoryBackupRoot\", [StringComparison]::OrdinalIgnoreCase)) {
        if (@(Get-ChildItem -LiteralPath $directory -Force).Count -gt 0) {
            break
        }
        Remove-Item -LiteralPath $directory -Force -ErrorAction Stop
        $directory = Split-Path $directory -Parent
    }
}

Write-Host "Snapshot cleanup complete for commit $Commit."
