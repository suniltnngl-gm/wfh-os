# AGENTS.md — delta-ops

Guidance for AI agents and humans working in this workspace.

> This is the primary protected workspace. Working files are guarded by **two
> independent systems**: **Git** (history, branches, commits) and **Windows File
> History** (uncommitted work, accidental edits/deletes, bad `git` operations).
> Preserve both.

## Required workflow

**Before making any edit to workspace files, run the Windows File History
backup first.** This ensures a version of the pre-edit file is captured, so the
old state remains recoverable even if the edit is later reverted or lost.

Before running the backup:

1. Ensure the exclusion list (below) is correctly applied.
2. Run the backup.
3. Proceed with the edit.

### Automation

Use the scripts in `scripts/` to refresh exclusions and back up in one step:

```powershell
# Refresh exclusions, restart File History, and run a backup
.\scripts\Update-WFHExclusions.ps1
fhmanagew.exe -backupnow

# Optional: Git snapshot (review changes before committing)
.\scripts\Start-DeltaOpsBackup.ps1
```

**Safe Git alias** — review changes before adding, instead of `git add .`:

```powershell
function git-safe {
    git status
    Write-Host ""
    Write-Host "Review changes before adding."
}
```

## Layout

- Root: `C:\Users\sunilkr.DESKTOP-0AM7VDP\Projects\delta-ops`
- Git repositories may live as individual repos here, or this directory may be a
  repository root itself.
- Windows File History backs up this directory; sibling user-profile folders
  (Desktop, Downloads, Documents, OneDrive, etc.) are **not** assumed protected.

## File History exclusion list

Exclude regenerable artifacts so backup storage stays lean:

| Entry | Why excluded |
|-------|--------------|
| `.git` | Git history is protected by Git itself |
| `node_modules` | Rebuildable |
| `.venv`, `__pycache__` | Rebuildable |
| `dist`, `build`, `bin`, `obj` | Build output |
| `.coverage`, `pytest_cache` | Test artifacts |
| `.next`, `.nuxt` | Framework build output |

**Do not auto-exclude anything solely because it appears in `.gitignore`.**
Secrets/config still worth backing up despite being gitignored:

- `.env`
- `*.local.db` / SQLite databases
- `settings.json`
- machine-specific configuration

Decide case-by-case.

> Exclusions only take effect after the folder exists. **Before running
> File History:** discover targets, update exclusions, then run the backup.

## Git guidance

### Safe

```bash
git status
git add <explicit paths>
git commit
git push
```

### Use with caution (risk to uncommitted work)

```bash
git add .
git add -A
git clean -fd
git reset --hard
git checkout .
git restore .
```

When in doubt, back up uncommitted work first — File History is the safety net,
but prefer not to rely on it.

## Recovery hierarchy

1. **Git committed history** — source of truth for all commits, branches, history  
2. **Windows File History** — safety net for uncommitted work, accidental edits, bad `git` operations  
3. **Remote Git repository** — disaster recovery when local Git is corrupted  
4. **E: drive store** — local recovery when everything else fails  

> Never assume a backup exists.  
> Always verify with a real restore test.

## Validation

After changing backup configuration, prove it works:

1. Create a test file in the workspace.
2. Run File History.
3. Confirm the file appears under
   `FileHistory\<user>\<computer>\Data`.
4. Confirm excluded content is **not** backed up.
5. Confirm versioned copies are created for modified files.

Never assume a backup configuration works without validation.