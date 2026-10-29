# Recovery-FileHistory.md

Recover from **File History** problems (backup corruption, service failure, etc.).

## Scenario: Lost a working file after a bad `git reset --hard`

**Fix:** Restore from File History.

1. Open File History in Windows Explorer.
2. Navigate to the project folder.
3. Find the version of the file from before the reset.
4. Copy it back to the working directory.

> 💡 **Tip:** File History stores multiple versions under `FileHistory\<user>\<computer>\Data`. The most recent version is usually the one you want.

---

## Scenario: Entire project folder deleted

**Fix:** Restore from Git (Layer 1) — this is the primary recovery path.

```bash
git clone <original-repo-url> <project-folder>
```

---

## Scenario: E: drive failure (local backup store lost)

**Fix:** Restore from **Git remote** (if you have a remote) or from **File History** (if the E: drive is the only local backup).

1. If you have a remote repository, push your changes back:
   ```bash
git push origin main
```
2. If you only have local backups, restore from File History.

---

## Scenario: File History service crashed

**Fix:** Restart the service and re-run the backup.

```powershell
# Restart File History service
Restart-Service fhsvc

# Run backup
fhmanagew.exe -backupnow
```

---

## Recovery hierarchy (order of operations)

1. **Git committed history** — first attempt for committed work
2. **File History** — for uncommitted work before `git restore`/`reset`
3. **Remote Git repository** — if local Git is corrupted
4. **E: drive store** — local recovery when everything else fails
