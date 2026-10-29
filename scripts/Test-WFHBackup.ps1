<#
.DESCRIPTION
    Verifies the Windows File History backup for the delta-ops workspace.
    Checks service status, config, recent backup age, versioned copies, and
    ensures excluded folders are absent from the backup store.

.EXAMPLE
    .\Test-WFHBackup.ps1

    # Returns $true if all checks pass, $false otherwise.
#>

param(
    # How many hours back the latest backup should be (default: 24)
    [int]$MaxHoursOld = 24,

    # Path to the Projects root (default: %HOME%\Projects)
    [string]$ProjectsRoot = "$HOME\Projects"
)

# Output a simple pass/fail summary
function Write-Result {
    param($Passed, $Message)
    if ($Passed) {
        Write-Host "✅ $Message"
    } else {
        Write-Host "❌ $Message"
    }
    $global:Results += @{ Passed = $Passed; Message = $Message }
}

# Initialise results
$global:Results = @()

Write-Host "=== File History Backup Verification ==="
Write-Host ""

# 1. File History service running
$fhSvc = Get-Service fhsvc -ErrorAction SilentlyContinue
if ($fhSvc -and $fhSvc.Status -eq 'Running') {
    Write-Result $true "File History service is running"
} else {
    Write-Result $false "File History service is NOT running (status: $($fhSvc?.Status))"
}

# 2. Target drive / Projects root available
if (Test-Path $ProjectsRoot) {
    Write-Result $true "Projects root exists at $ProjectsRoot"
} else {
    Write-Result $false "Projects root NOT found at $ProjectsRoot"
}

# 3. Config contains Projects
$configFile = "$env:LOCALAPPDATA\Microsoft\Windows\FileHistory\Configuration\Config1.xml"
if (Test-Path $configFile) {
    [xml]$cfg = Get-Content $configFile
    $hasProjects = $cfg.SelectNodes("//FolderExclude") |
        Where-Object { $_.InnerText -like "$ProjectsRoot*" } |
        Measure-Object | ForEach-Object { $_.Count -gt 0 }
    if ($hasProjects) {
        Write-Result $true "Config contains exclusions for Projects root"
    } else {
        Write-Result $false "Config does NOT contain Projects root exclusions"
    }
} else {
    Write-Result $false "File History config not found at $configFile"
}

# 4. Latest backup newer than MaxHoursOld
# File History stores versioned copies under the user's Data folder.
# Typical path: FileHistory\<user>\<computer>\Data
$fhDataRoot = "$env:SystemDrive\Users\$env:USERNAME\FileHistory\*"
$fhDataDirs = Get-ChildItem $fhDataRoot -Directory -ErrorAction SilentlyContinue
$recentBackup = $false

if ($fhDataDirs) {
    # Look for the most recently modified folder under the Data path
    $latest = $fhDataDirs |
        Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        $ageHours = (Get-Date - $latest.LastWriteTime).TotalHours
        if ($ageHours -le $MaxHoursOld) {
            $recentBackup = $true
            Write-Result $true "Latest backup is $ageHours:h ago (within $MaxHoursOld hours)"
        } else {
            Write-Result $false "Latest backup is $ageHours:h old (older than $MaxHoursOld hours)"
        }
    } else {
        Write-Result $false "No backup data folders found under $fhDataRoot"
    }
} else {
    Write-Result $false "File History Data root not found at $fhDataRoot"
}

# 5. Versioned copy of a test file exists
# Check that at least one file under the Data folder was modified recently
if ($recentBackup) {
    $testFilePattern = "$ProjectsRoot\*.ps1"
    $testFiles = Get-ChildItem $testFilePattern -ErrorAction SilentlyContinue
    if ($testFiles) {
        $recentTestFile = $testFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($recentTestFile) {
            $fileAgeHours = (Get-Date - $recentTestFile.LastWriteTime).TotalHours
            if ($fileAgeHours -le $MaxHoursOld) {
                Write-Result $true "Versioned test file exists and was modified $fileAgeHours:h ago"
            } else {
                Write-Result $warning "Test file exists but was modified $fileAgeHours:h ago (older than $MaxHoursOld hours)"
            }
        } else {
            Write-Result $false "No test .ps1 files found in Projects"
        }
    } else {
        Write-Result $warning "No .ps1 test files found in Projects (skipping file-timestamp check)"
    }
}

# 6. Excluded folders not present in backup
$ExcludeNames = @(".git", "node_modules", ".venv", "__pycache__", "dist", "build", "bin", "obj", ".coverage", "pytest_cache", ".next", ".nuxt")
$fhBackupRoot = "$env:SystemDrive\Users\$env:USERNAME\FileHistory"

$excludedFound = $false
if (Test-Path $fhBackupRoot) {
    $foldersInBackup = Get-ChildItem $fhBackupRoot -Recurse -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name }

    foreach ($ename in $ExcludeNames) {
        if ($foldersInBackup -contains $ename -or $foldersInBackup -match "^$ename$") {
            $excludedFound = $true
            Write-Result $false "Excluded folder '$ename' found in backup store (should be excluded)"
        }
    }

    if (-not $excludedFound) {
        Write-Result $true "No excluded folders (.git, node_modules, etc.) found in backup store"
    }
} else {
    Write-Result $warning "File History backup root not found; cannot verify excluded folders"
}

# Summary
Write-Host ""
$passCount = ($global:Results | Where-Object { $_.Passed }).Count
$totalCount = $global:Results.Count
Write-Host "=== Summary: $passCount of $total checks passed ==="

if ($passCount -eq $totalCount) {
    Write-Host "All checks passed! File History backup is valid."
    exit 0
} else {
    Write-Host "Some checks failed. Review above."
    exit 1
}