<#
.DESCRIPTION
    Rebuilds the Projects subtree exclusions used by Windows File History.
    Exclusion discovery prunes excluded directories, so nested cache folders do
    not create redundant rules.

.EXAMPLE
    .\Update-WFHExclusions.ps1
#>

[CmdletBinding()]
param(
    [string]$ProjectsRoot = "$HOME\Projects"
)

$ErrorActionPreference = "Stop"

$ExcludeNames = @(
    ".git",
    "node_modules",
    ".venv",
    "__pycache__",
    "dist",
    "build",
    "bin",
    "obj",
    ".coverage",
    "pytest_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".mypy_cache",
    "htmlcov",
    ".next",
    ".nuxt",
    ".opencode-os-backup"
)

$ProjectsRoot = (Resolve-Path -LiteralPath $ProjectsRoot).Path.TrimEnd('\')
$configDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\FileHistory\Configuration"
$configFiles = @(
    (Join-Path $configDirectory "Config1.xml"),
    (Join-Path $configDirectory "Config2.xml")
)

foreach ($configFile in $configFiles) {
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        throw "File History configuration not found: $configFile"
    }
}

$excludeSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($name in $ExcludeNames) {
    [void]$excludeSet.Add($name)
}

$targets = [System.Collections.Generic.List[string]]::new()
$pending = [System.Collections.Generic.Stack[string]]::new()
$pending.Push($ProjectsRoot)

while ($pending.Count -gt 0) {
    $current = $pending.Pop()
    foreach ($directory in Get-ChildItem -LiteralPath $current -Directory -Force) {
        if ($excludeSet.Contains($directory.Name) -or $directory.Name.EndsWith(".egg-info", [System.StringComparison]::OrdinalIgnoreCase)) {
            $targets.Add($directory.FullName.TrimEnd('\'))
            continue
        }

        if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
            $pending.Push($directory.FullName)
        }
    }
}

$desired = @($targets | Sort-Object -Unique)
$configChanged = $false

foreach ($configFile in $configFiles) {
    [xml]$config = Get-Content -LiteralPath $configFile
    $existingNodes = @(
        $config.SelectNodes("//FolderExclude") |
            Where-Object {
                $_.InnerText.Equals($ProjectsRoot, [StringComparison]::OrdinalIgnoreCase) -or
                $_.InnerText.StartsWith("$ProjectsRoot\", [StringComparison]::OrdinalIgnoreCase)
            }
    )
    $existingPaths = @($existingNodes | ForEach-Object { $_.InnerText } | Sort-Object -Unique)

    $same = $existingNodes.Count -eq $desired.Count -and $existingPaths.Count -eq $desired.Count
    if ($same) {
        for ($index = 0; $index -lt $desired.Count; $index++) {
            if (-not $existingPaths[$index].Equals($desired[$index], [StringComparison]::OrdinalIgnoreCase)) {
                $same = $false
                break
            }
        }
    }

    if ($same) {
        continue
    }

    foreach ($node in $existingNodes) {
        [void]$node.ParentNode.RemoveChild($node)
    }

    foreach ($path in $desired) {
        $node = $config.CreateElement("FolderExclude")
        $node.InnerText = $path
        [void]$config.DataProtectionUserConfig.AppendChild($node)
    }

    $config.Save($configFile)
    $configChanged = $true
}

Write-Host "Projects exclusion rules: $($desired.Count) unique directories."
if ($configChanged) {
    Write-Host "File History exclusions updated. The next backup run will use the refreshed configuration."
} else {
    Write-Host "Exclusions are already current."
}
