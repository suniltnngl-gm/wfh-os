<#
.DESCRIPTION
    One-command workflow for the delta-ops workspace:
    1. Refresh File History exclusions (Update-WFHExclusions.ps1)
    2. Run a File History backup
    3. Optional: Git snapshot (status + commit + push)

.EXAMPLE
    # Full automated workflow with auto-commit
    .\Start-DeltaOpsBackup.ps1 -AutoCommit

.EXAMPLE
    # Manual review before committing
    .\Start-DeltaOpsBackup.ps1
#>

param(
    [Switch]$AutoCommit
)

# 1. Refresh exclusions & backup
.\Update-WFHExclusions.ps1 -AutoCommit:$AutoCommit

fhmanagew.exe -backupnow

# 2. Optional: Git snapshot (status + commit + push)
Set-Location "$HOME\Projects"

Write-Host "Review changes before committing:"
git status

# Safe Git alias - use this instead of git add .
function git-safe {
    git status
    Write-Host ""
    Write-Host "Review changes before adding."
}

if (-not $AutoCommit) {
    Write-Host ""
    Write-Host "Manual commit (if desired):"
    Write-Host "    git add ."
    Write-Host "    git commit -m \"backup: $(Get-Date -Format 'yyyy-MM-dd HH:mm')\""
    Write-Host "    git push"
}

Write-Host ""
Write-Host "✅ Workflow complete."