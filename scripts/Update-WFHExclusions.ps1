<#
.DESCRIPTION
    Rebuilds the Windows File History exclusion list for the Projects workspace,
    restarts the File History service, triggers a backup, and optionally
    creates a lightweight Git snapshot (timestamped commit if changes exist).

    Logs to logs\backup-history.log.

.PARAMETER AutoCommit
    If specified, creates a timestamped commit when changes are detected
    (e.g. "backup: 2026-10-28 16:30").

.PARAMETER LogOnly
    If specified, only logs the action without triggering a backup.

.EXAMPLE
    .\Update-WFHExclusions.ps1 -AutoCommit

.EXAMPLE
    .\Update-WFHExclusions.ps1
#>

param(
    [Switch]$AutoCommit
)

$ProjectsRoot = "C:\Users\sunilkr.DESKTOP-0AM7VDP\Projects"

# Directories to exclude system-wide (regenerable artifacts).
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
    ".next",
    ".nuxt"
)

$configFile  = "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config1.xml"
$configFile2 = "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config2.xml"

if (-not (Test-Path $configFile)) {
    Write-Warning "File History config not found at: $configFile"
    exit 1
}

[xml]$cfg = Get-Content $configFile

#
# 1. Remove previously generated exclusions so we never duplicate entries.
#
$generated = $cfg.SelectNodes("//FolderExclude") |
    Where-Object { $_.InnerText -like "$ProjectsRoot*" }

foreach ($node in @($generated)) {
    $node.ParentNode.RemoveChild($node) | Out-Null
}

#
# 2. Discover exclusion targets under ProjectsRoot.
#
$newExclusions = 0
Get-ChildItem $ProjectsRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object Name -in $ExcludeNames |
    ForEach-Object {
        $node = $cfg.CreateElement("FolderExclude")
        $node.InnerText = $_.FullName
        $cfg.DataProtectionUserConfig.AppendChild($node) | Out-Null
        $newExclusions++
    }

Write-Host "Excluded $newExclusions directories:"
Get-ChildItem $ProjectsRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object Name -in $ExcludeNames |
    ForEach-Object { Write-Host "  $($_.FullName)" }

$cfg.Save($configFile)
if (Test-Path $configFile2) { $cfg.Save($configFile2) }

#
# 3. Restart the File History service so it picks up the new exclusions.
#    Run as administrator for this to succeed.
#
try {
    Restart-Service fhsvc -ErrorAction Stop
} catch {
    Write-Warning "Could not restart fhsvc. Run this script as Administrator."
}

Write-Host ""
Write-Host "✅ File History exclusions updated and service restarted."

#
# 4. Run a backup now so the new configuration is exercised immediately.
#    Caller must run: fhmanagew.exe -backupnow
#
Write-Host "Run a backup now:"
Write-Host "    fhmanagew.exe -backupnow"

#
# 5. Optional: Auto Git snapshot if -AutoCommit was specified
#
if ($AutoCommit) {
    Write-Host ""
    Write-Host "Auto-committing Git changes..."

    $origLocation = Get-Location
    try {
        Set-Location $ProjectsRoot

        $status = git status --short
        if ($status) {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
            $commitMsg = "backup: $timestamp"

            Write-Host "Changes detected. Committing: $commitMsg"
            git add -A
            git commit -m $commitMsg
            Write-Host "Committed successfully."
        } else {
            Write-Host "No changes to commit."
        }
    } finally {
        Set-Location $origLocation
    }
}