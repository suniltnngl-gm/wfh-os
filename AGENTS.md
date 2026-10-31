# AGENTS.md — delta-ops

Guidance for AI agents and humans working in this workspace.

> Protect work with Git commits, verified pre-edit snapshots in the external
> `.opencode-os-backup` folder, and Windows File History as an independent
> background recovery layer.

## Required workflow

**Before editing an existing file, save a verified snapshot outside the
repository:**

```powershell
.\scripts\Save-PreEditSnapshot.ps1 -Paths @(
    "AGENTS.md",
    "scripts\Start-DeltaOpsBackup.ps1"
)
```

Paths may be repository-relative or absolute paths inside the repository.
Snapshots are written to
`C:\Users\sunilkr.DESKTOP-0AM7VDP\Projects\other\.opencode-os-backup\<repo>\`
using the original directory layout and names such as `file.ps1.bak1`,
`file.ps1.bak2`. Each copy is SHA-256 verified before editing. New files have
no pre-edit content to snapshot.

The current File History policy excludes
`C:\Users\sunilkr.DESKTOP-0AM7VDP\Projects\other\.opencode-os-backup`; the
external `.bakN` copies are therefore a separate local safety layer, not files
backed up by WFH. File History covers included source-project paths, subject
to its own exclusions and the actual version check.

The save command first reports each path's Git index/ignore state, File History
include/exclude rule and available version, and external snapshot count. To
audit a repository at any time:

```powershell
.\scripts\Test-ProtectionCoverage.ps1 -ShowExclusions
.\scripts\Test-ProtectionCoverage.ps1 -Paths @("AGENTS.md")
```

Git and File History exclusions are separate policies, not mirrored
automatically. Git-ignore rules keep files out of commits; File History
exclusions omit folders from backup. Review them independently before adding
or changing either policy.

The pre-commit hook requires snapshots for staged modifications, deletions,
and rename sources, and rejects staged content that differs from the working
tree. The post-commit hook removes snapshots only for paths included in the
successful commit. Snapshots for other uncommitted work remain. If cleanup
fails, the commit has still succeeded; rerun
`scripts\Clean-CommittedSnapshots.ps1` to clean the latest commit.

### Automation

File History scripts remain available for manual maintenance and independent
backup checks; they are not required before edits or run by Git hooks:

```powershell
# Optional File History backup
.\scripts\Start-DeltaOpsBackup.ps1

# Optional exact File History verification
.\scripts\Start-DeltaOpsBackup.ps1 -Paths @("C:\path\to\file")

# Optional File History activity check
.\scripts\Schedule-WFHBackup.ps1
```

Install the shared pre-commit and post-commit hooks once in the WFH and
adapter repositories:

```powershell
.\scripts\Install-WFHPreCommitHook.ps1
```

Git hooks do not invoke File History or create snapshots automatically. Save
snapshots before editing; the pre-commit hook verifies them and the
post-commit hook cleans committed snapshots.

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
| `.coverage`, `pytest_cache`, `.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `htmlcov` | Test and lint artifacts |
| `dist`, `build`, `bin`, `obj`, `*.egg-info` | Build output and package metadata |
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

When in doubt, run `Save-PreEditSnapshot.ps1` for the exact existing files
before editing. File History is an independent recovery layer, not a substitute
for an intentional pre-edit snapshot.

## Recovery hierarchy

1. **Git committed history** — source of truth for all commits, branches, history
2. **External `.bakN` snapshots** — short-term recovery for uncommitted edits
3. **Windows File History** — recovery for included source files; it does not back up the excluded `.opencode-os-backup` snapshot store
4. **Remote Git repository** — disaster recovery when local Git is corrupted
5. **E: drive store** — local recovery when everything else fails

> Never assume a backup exists.  
> Always verify with a real restore test.

## Validation

After changing snapshot or hook logic, use a temporary Git repository to verify
that:

1. Repeated pre-edit saves create `.bak1`, `.bak2`, and exact SHA-256 matches.
2. Pre-commit rejects modified files without snapshots and accepts protected
   staged files.
3. Failed commits retain snapshots.
4. Successful commits remove snapshots only for committed paths.

Run File History health and restore checks separately when changing its
configuration; Git hooks do not invoke File History.