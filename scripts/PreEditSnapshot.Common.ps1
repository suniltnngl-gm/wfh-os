function Get-RepositoryRoot {
    param([string]$RepositoryRoot)

    if (-not $RepositoryRoot) {
        $RepositoryRoot = (& git rev-parse --show-toplevel).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $RepositoryRoot) {
            throw "Could not determine the Git repository root."
        }
    }

    $RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
        throw "Repository directory not found: $RepositoryRoot"
    }

    return $RepositoryRoot
}

function Get-DefaultBackupRoot {
    if ($env:OPENCODE_OS_BACKUP_ROOT) {
        return $env:OPENCODE_OS_BACKUP_ROOT
    }
    return Join-Path $HOME "Projects\other\.opencode-os-backup"
}

function Assert-BackupRootOutsideRepository {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BackupRoot
    )

    $snapshotRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $BackupRoot (Split-Path $RepositoryRoot -Leaf))
    ).TrimEnd('\')
    if ($snapshotRoot.Equals($RepositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $snapshotRoot.StartsWith("$RepositoryRoot\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "The pre-edit snapshot directory must be outside the Git repository: $snapshotRoot"
    }
}

function ConvertTo-RepositoryRelativePath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $Path))
    }
    $prefix = "$RepositoryRoot\"
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the repository: $Path"
    }

    return $candidate.Substring($prefix.Length)
}

function Get-SnapshotDirectory {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$BackupRoot
    )

    Assert-BackupRootOutsideRepository -RepositoryRoot $RepositoryRoot -BackupRoot $BackupRoot
    $repositoryName = Split-Path $RepositoryRoot -Leaf
    $relativeDirectory = Split-Path $RelativePath -Parent
    $directory = Join-Path (Join-Path $BackupRoot $repositoryName) $relativeDirectory
    return $directory
}

function Get-SnapshotFiles {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$BackupRoot
    )

    $directory = Get-SnapshotDirectory -RepositoryRoot $RepositoryRoot `
        -RelativePath $RelativePath -BackupRoot $BackupRoot
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        return @()
    }

    $fileName = Split-Path $RelativePath -Leaf
    $pattern = '^' + [regex]::Escape($fileName) + '\.bak([1-9][0-9]*)$'
    return @(
        Get-ChildItem -LiteralPath $directory -File |
            Where-Object { $_.Name -match $pattern } |
            Sort-Object { [long]([regex]::Match($_.Name, $pattern).Groups[1].Value) }
    )
}

function Get-ContentSha256 {
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
