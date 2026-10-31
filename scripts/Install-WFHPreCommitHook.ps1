<#
.DESCRIPTION
    Installs the shared snapshot-verification pre-commit and post-commit hooks
    in the WFH and Colab adapter repositories without changing tracked files.

.EXAMPLE
    .\Install-WFHPreCommitHook.ps1

.EXAMPLE
    .\Install-WFHPreCommitHook.ps1 -RepositoryPaths @("C:\path\to\repo")
#>

[CmdletBinding()]
param(
    [string[]]$RepositoryPaths = @(
        "$HOME\Projects\wfh-os",
        "$HOME\Projects\colab-mcp-adapter"
    ),
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$hookDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\.githooks")).Path
$normalizedHookDirectory = [System.IO.Path]::GetFullPath($hookDirectory).Replace('/', '\').TrimEnd('\')

foreach ($repositoryPath in $RepositoryPaths) {
    $repository = (Resolve-Path -LiteralPath $repositoryPath).Path
    & git -C $repository rev-parse --show-toplevel *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Not a Git repository: $repository"
    }

    $currentPath = & git -C $repository config --local --get core.hooksPath
    $normalizedCurrentPath = if ($currentPath) {
        [System.IO.Path]::GetFullPath($currentPath.Trim()).Replace('/', '\').TrimEnd('\')
    } else {
        ""
    }
    if ($Uninstall) {
        if ($normalizedCurrentPath -and
            $normalizedCurrentPath.Equals($normalizedHookDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            & git -C $repository config --local --unset core.hooksPath
            if ($LASTEXITCODE -ne 0) {
                throw "Could not remove core.hooksPath from $repository."
            }
            Write-Host "Removed shared pre-commit hook from $repository."
        } else {
            Write-Host "No shared hook configuration to remove from $repository."
        }
        continue
    }

    if ($normalizedCurrentPath -and
        -not $normalizedCurrentPath.Equals($normalizedHookDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace existing core.hooksPath '$($currentPath.Trim())' in $repository."
    }

    & git -C $repository config --local core.hooksPath $hookDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install shared pre-commit hook in $repository."
    }
    Write-Host "Installed shared snapshot hooks in $repository."
}
