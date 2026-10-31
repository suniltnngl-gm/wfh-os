# Recovery-Disaster.md

Disaster recovery scenarios covering **local** and **remote** failures.

## Scenario: E: drive failure (backup store destroyed)

**Recovery path:** Git remote → Recreate local File History → Update E: drive if possible.

1. **Recover from remote Git** — check if you have a remote:
   ```bash
   git remote -v
   git clone <remote-url>
   ```
2. **Recreate local File History** — the service may auto-create backups on the new E: drive.
3. **Update AGENTS.md** exclusions after restoring.

---

## Scenario: Complete Fileset deletion (all projects gone)

**Recovery path:** Git remote (historical version control) → File History (latest) → Recent backup (E: drive).

1. **Git remote** — the source of truth for history:
   ```bash
   git clone <original-repo-url> <project-name>
   ```
2. **File History** — for recent uncommitted changes:
   ```powershell
   # Manual File History restore using Windows Explorer
   # Navigate to FileHistory\<user>\<computer>\Data
   ```
3. **E: drive** — if you have backed up local uncommitted work, restore the most recent snapshot.

---

## Scenario: Windows reinstall or system crash

**Recovery path:** Git remote → File History (restored drive) → Local E: drive backup.

1. **Git remote** — most reliable disaster recovery:
   ```bash
   git clone <original-repo-url>
   ```
2. **File History / external snapshots** — restore C: drive if available; check `.bakN` files under `.opencode-os-backup` for uncommitted edits.
3. **E: drive** — restore the local backup store if your E: drive is portable.

---

## Recovery hierarchy (order of operations)

1. **Git committed history** — first attempt for committed work
2. **External `.bakN` snapshots** — short-term recovery for uncommitted edits
3. **File History** — independent recovery if local files or snapshots are lost
4. **Remote Git repository** — if local Git is corrupted
5. **E: drive store** — local recovery when everything else fails

> 💡 **Pro tip:** Keep your Git remote URL in a secure location (e.g., secrets manager). If you lose access to the remote, you may need to ask the repo owner to re-share access or manually copy backups from the E: drive.

---

## Tools and commands

### Git helpers

```powershell
function git-safe {
    git status
    Write-Host ""
    Write-Host "Review changes before adding."
}

function git-log {
    git log --oneline --all --graph --decorate
}
```

### File History helpers

```powershell
# Refresh exclusions, request a backup, and wait for File History activity
.\scripts\Start-DeltaOpsBackup.ps1

# List backups
$volume = Get-Volume -FileSystemLabel "WFH"
Get-ChildItem "$($volume.DriveLetter):\FileHistory\$env:USERNAME\$env:COMPUTERNAME\Data" -Directory
```

> After recovery, verify the restored Git worktree, inspect any external
> `.bakN` snapshots, and optionally run `Start-DeltaOpsBackup.ps1` to request
> an independent File History backup. It never creates Git commits.

---

## Emergency plan checklist

- [ ] Keep remote Git URL in secrets store
- [ ] Test disaster recovery quarterly (remote clone + restore)
- [ ] Update backup exclusions after any recovery
- [ ] Verify File History service is running and E: drive is online