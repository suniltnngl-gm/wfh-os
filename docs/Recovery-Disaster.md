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
2. **File History** — restore C: drive if available, then run `Update-WFHExclusions.ps1 -AutoCommit`
3. **E: drive** — restore the local backup store if your E: drive is portable.

---

## Recovery hierarchy (order of operations)

1. **Git committed history** — first attempt for committed work
2. **File History** — for uncommitted work before `git restore`/`reset`
3. **Remote Git repository** — if local Git is corrupted
4. **E: drive store** — local recovery when everything else fails

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
# Restart service
Restart-Service fhsvc

# Run backup
fhmanagew.exe -backupnow

# List backups
Get-ChildItem "FileHistory\$env:USERNAME\*" -Directory
```

> 🚀 **Remember:** After any disaster recovery, run `Update-WFHExclusions.ps1 -AutoCommit` to get back to a known-good exclusion state.

---

## Emergency plan checklist

- [ ] Keep remote Git URL in secrets store
- [ ] Test disaster recovery quarterly (remote clone + restore)
- [ ] Update backup exclusions after any recovery
- [ ] Verify File History service is running and E: drive is online