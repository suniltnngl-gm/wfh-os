<#
.DESCRIPTION
    Reports Git tracking, File History coverage, external snapshot state, and
    the separate exclusion rules for the selected repository.

.EXAMPLE
    .\Test-ProtectionCoverage.ps1 -Paths @("AGENTS.md", "scripts\Save-PreEditSnapshot.ps1")

.EXAMPLE
    .\Test-ProtectionCoverage.ps1 -ShowExclusions
#>

[CmdletBinding()]
param(
    [string[]]$Paths = @(),
    [string]$PathsFile = "",
    [string]$RepositoryRoot = "",
    [string]$BackupRoot = "",
    [switch]$ShowExclusions
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

$configDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\FileHistory\Configuration"
$configFiles = @(
    (Join-Path $configDirectory "Config1.xml"),
    (Join-Path $configDirectory "Config2.xml")
)
$fileHistoryConfigs = [System.Collections.Generic.List[object]]::new()
foreach ($configFile in $configFiles) {
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        throw "File History configuration not found: $configFile"
    }
    [xml]$xmlDoc = Get-Content -LiteralPath $configFile
    $includes = @(
        $xmlDoc.SelectNodes("//UserFolder | //Library") |
            ForEach-Object {
                foreach ($match in [regex]::Matches($_.InnerText, '[A-Za-z]:\\.*?(?=[A-Za-z]:\\|$)')) {
                    $match.Value.TrimEnd('\')
                }
            } |
            Sort-Object -Unique
    )
    $excludes = @(
        $xmlDoc.SelectNodes("//FolderExclude") |
            ForEach-Object { $_.InnerText.TrimEnd('\') } |
            Sort-Object -Unique
    )
    $fileHistoryConfigs.Add([pscustomobject]@{
        Path = $configFile
        Includes = $includes
        Excludes = $excludes
    })
}

function Get-FileHistoryCoverageRule {
    param([Parameter(Mandatory)][string]$FullPath)

    $states = foreach ($config in $fileHistoryConfigs) {
        $isExcluded = @(
            $config.Excludes | Where-Object {
                $FullPath.Equals($_, [StringComparison]::OrdinalIgnoreCase) -or
                $FullPath.StartsWith("$_\", [StringComparison]::OrdinalIgnoreCase)
            }
        ).Count -gt 0
        if ($isExcluded) {
            "Excluded"
            continue
        }

        $isIncluded = @(
            $config.Includes | Where-Object {
                $FullPath.Equals($_, [StringComparison]::OrdinalIgnoreCase) -or
                $FullPath.StartsWith("$_\", [StringComparison]::OrdinalIgnoreCase)
            }
        ).Count -gt 0
        if ($isIncluded) {
            "Included"
        } else {
            "NotIncluded"
        }
    }

    if (($states | Sort-Object -Unique).Count -gt 1) {
        return "ConfigMismatch"
    }
    return $states[0]
}

function Get-GitCoverage {
    param([Parameter(Mandatory)][string]$RelativePath)

    $trackedPaths = @(& git -C $RepositoryRoot ls-files --cached -- $RelativePath)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not query the Git index for '$RelativePath'."
    }
    if ($trackedPaths.Count -gt 0) {
        $gitState = "Tracked"
        $ignoreReason = ""
    } else {
        $ignoreDetails = @(& git -C $RepositoryRoot check-ignore -v -- $RelativePath 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $gitState = "Ignored"
            $ignoreReason = ($ignoreDetails -join "; ")
        } else {
            $gitState = "Untracked"
            $ignoreReason = ""
        }
    }

    $status = @(& git -C $RepositoryRoot status --short -- $RelativePath)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Git status for '$RelativePath'."
    }
    $gitStatus = if ($status.Count -gt 0) { ($status -join "; ").Trim() } else { "clean" }
    return [pscustomobject]@{
        State = $gitState
        Status = $gitStatus
        IgnoreReason = $ignoreReason
    }
}

function Get-FileHistoryCopiesForPath {
    param([Parameter(Mandatory)][string]$FullPath)

    $volume = Get-Volume -FileSystemLabel "WFH" -ErrorAction Stop
    if (@($volume).Count -ne 1 -or -not $volume.DriveLetter) {
        throw "Expected one mounted File History volume labeled WFH."
    }
    $root = [System.IO.Path]::GetPathRoot($FullPath)
    $drive = $root.TrimEnd(':\')
    $relative = $FullPath.Substring($root.Length).TrimStart('\')
    $backupPath = Join-Path "$($volume.DriveLetter):\FileHistory\$env:USERNAME\$env:COMPUTERNAME\Data" (
        Join-Path $drive $relative
    )
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

function Get-FileHashOrEmpty {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ""
    }
    return Get-ContentSha256 -Path $Path
}

if ($Paths.Count -eq 0) {
    $Paths = @(& git -C $RepositoryRoot ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not enumerate repository files."
    }
}

if ($ShowExclusions) {
    Write-Host "Git ignore rules:"
    $ignoreFiles = @(
        (Join-Path $RepositoryRoot ".gitignore"),
        (& git -C $RepositoryRoot rev-parse --git-path info/exclude)
    )
    $globalIgnore = & git -C $RepositoryRoot config --path --get core.excludesFile 2>$null
    if ($LASTEXITCODE -eq 0 -and $globalIgnore) {
        $ignoreFiles += $globalIgnore
    }
    $foundGitRules = $false
    foreach ($ignoreFile in $ignoreFiles | Where-Object { $_ } | Sort-Object -Unique) {
        $resolvedIgnoreFile = if ([System.IO.Path]::IsPathRooted($ignoreFile)) {
            $ignoreFile
        } else {
            Join-Path $RepositoryRoot $ignoreFile
        }
        if (Test-Path -LiteralPath $resolvedIgnoreFile -PathType Leaf) {
            $rules = @(Get-Content -LiteralPath $resolvedIgnoreFile | Where-Object { $_ -and -not $_.StartsWith("#") })
            if ($rules.Count -gt 0) {
                $foundGitRules = $true
                Write-Host "  $resolvedIgnoreFile"
                $rules | ForEach-Object { Write-Host "    $_" }
            }
        }
    }
    if (-not $foundGitRules) {
        Write-Host "  (no Git ignore rules found)"
    }

    Write-Host "Windows File History include/exclude rules:"
    foreach ($historyConfig in $fileHistoryConfigs) {
        Write-Host "  $($historyConfig.Path)"
        Write-Host "    Included roots:"
        $historyConfig.Includes | ForEach-Object { Write-Host "      $_" }
        Write-Host "    Excluded folders:"
        $historyConfig.Excludes | ForEach-Object { Write-Host "      $_" }
    }
    if (($fileHistoryConfigs[0].Includes -join "`n") -ne ($fileHistoryConfigs[1].Includes -join "`n") -or
        ($fileHistoryConfigs[0].Excludes -join "`n") -ne ($fileHistoryConfigs[1].Excludes -join "`n")) {
        Write-Warning "Config1.xml and Config2.xml have different File History rules."
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $Paths) {
    $relativePath = ConvertTo-RepositoryRelativePath -RepositoryRoot $RepositoryRoot -Path $path
    if (-not $seen.Add($relativePath)) {
        continue
    }
    $fullPath = Join-Path $RepositoryRoot $relativePath
    $git = Get-GitCoverage -RelativePath $relativePath
    $wfhRule = Get-FileHistoryCoverageRule -FullPath $fullPath
    $wfhCopies = @()
    $wfhCopyState = "NotChecked"
    if ($wfhRule -eq "Included") {
        $wfhCopies = @(Get-FileHistoryCopiesForPath -FullPath $fullPath)
        if ($wfhCopies.Count -eq 0) {
            $wfhCopyState = "NoVersionFound"
        } else {
            $currentHash = Get-FileHashOrEmpty -Path $fullPath
            $exactCopy = $false
            if ($currentHash) {
                $exactCopy = @(
                    $wfhCopies | Where-Object {
                        (Get-ContentSha256 -Path $_.FullName) -eq $currentHash
                    }
                ).Count -gt 0
            }
            $wfhCopyState = if ($exactCopy) { "ExactCurrentCopy" } else { "PriorVersionOnly" }
        }
    } elseif ($wfhRule -eq "Excluded") {
        $wfhCopyState = "Excluded"
    } elseif ($wfhRule -eq "ConfigMismatch") {
        $wfhCopyState = "ConfigMismatch"
    } else {
        $wfhCopyState = "NotIncluded"
    }

    $snapshots = @(Get-SnapshotFiles -RepositoryRoot $RepositoryRoot `
        -RelativePath $relativePath -BackupRoot $BackupRoot)
    $snapshotState = "NoSnapshot"
    $currentHash = Get-FileHashOrEmpty -Path $fullPath
    if ($snapshots.Count -gt 0) {
        if (-not $currentHash) {
            $snapshotState = "FileMissing"
        } elseif ((Get-ContentSha256 -Path $snapshots[-1].FullName) -eq $currentHash) {
            $snapshotState = "MatchesCurrent"
        } else {
            $snapshotState = "DoesNotMatchCurrent"
        }
    }
    $results.Add([pscustomobject]@{
        Path = $relativePath
        Git = $git.State
        GitWorktree = $git.Status
        GitIgnoreRule = $git.IgnoreReason
        FileHistoryRule = $wfhRule
        FileHistoryCopies = $wfhCopyState
        Snapshots = $snapshots.Count
        LatestSnapshotState = $snapshotState
    })
}

if ($results.Count -gt 0) {
    foreach ($result in $results) {
        $result | Format-List Path, Git, GitWorktree, GitIgnoreRule,
            FileHistoryRule, FileHistoryCopies, Snapshots, LatestSnapshotState
        if ($result.Git -eq "Ignored") {
            Write-Warning "Git ignores '$($result.Path)': $($result.GitIgnoreRule)"
        }
        if ($result.FileHistoryRule -ne "Included") {
            Write-Warning "File History does not include '$($result.Path)' (rule: $($result.FileHistoryRule))."
        } elseif ($result.FileHistoryCopies -eq "NoVersionFound") {
            Write-Warning "No File History version is currently available for '$($result.Path)'."
        }
    }
}
Write-Host "Coverage is based on Git index/ignore rules, File History Config1/Config2 roots and exclusions, and external .bakN snapshots."
Write-Host "File History configuration indicates coverage; a copy check only proves a matching local File History version exists."
