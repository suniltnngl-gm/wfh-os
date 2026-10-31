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

**Fix:** Use the WFH workflow to refresh exclusions, request a backup, and
wait for File History state transitions. Avoid manually restarting `fhsvc`;
service control may require elevation.

```powershell
.\scripts\Start-DeltaOpsBackup.ps1
```

---

## Before editing existing files

```powershell
.\scripts\Save-PreEditSnapshot.ps1 -Paths @(
    "scripts\Test-WFHBackup.ps1",
    "AGENTS.md"
)
```

Run before each new editing pass. The script verifies an exact SHA-256 copy
outside the repository and increments suffixes (`.bak1`, `.bak2`) so earlier
versions remain available until commit.

The WFH configuration excludes
`C:\Users\sunilkr.DESKTOP-0AM7VDP\Projects\other\.opencode-os-backup`; `.bakN`
copies are not themselves protected by File History. WFH remains a separate
recovery layer for included source files.

It also reports whether each path is Git-tracked, Git-ignored or untracked,
whether File History configuration includes/excludes it, whether a File
History version exists, and the current external snapshot count. Run
`Test-ProtectionCoverage.ps1 -ShowExclusions` to inspect Git and File History
rules separately.

The pre-commit hook requires snapshots for modified/deleted files and checks
that staged contents match the working tree. The post-commit hook removes
snapshots only for paths included in the successful commit. File History
remains an independent recovery layer and can be requested manually with
`Start-DeltaOpsBackup.ps1`.

---

## Recovery hierarchy (order of operations)

1. **Git committed history** — first attempt for committed work
2. **External `.bakN` snapshots** — short-term recovery for uncommitted edits
3. **File History** — independent recovery if local files or snapshots are lost
4. **Remote Git repository** — if local Git is corrupted
5. **E: drive store** — local recovery when everything else fails
