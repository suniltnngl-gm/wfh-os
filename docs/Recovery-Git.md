# Recovery-Git.md

Recover from **committed history** problems using Git.

## Scenario: Accidental bad commit / wrong branch

**Fix:** `git revert` (adds a new commit undoing the changes) or `git checkout`/`git switch` to move branches.

```bash
git revert <bad-commit-hash>
git commit -m "Revert bad commit"
```

---

## Scenario: Deleted file that was committed

**Fix:** Restore from Git history.

```bash
git log --oneline -- <file-path>
git checkout <commit-hash>~1 -- <file-path>
```

---

## Scenario: Unwanted local changes (modified working tree)

**Fix:** Discard uncommitted changes carefully.

```bash
# See what changed first
git diff

# Discard changes to specific file
git checkout -- <file-path>

# Discard all unstaged changes
git restore .
```

> ⚠️ **Warning:** `git restore .` and `git checkout .` destroy uncommitted work.
> Use **File History** (Layer 2) as the safety net for uncommitted changes before running these.

---

## Recovery hierarchy (order of operations)

1. **Git committed history** — first attempt for committed work
2. **File History** — for uncommitted work before `git restore`/`reset`
3. **Remote Git repository** — if local Git is corrupted
4. **File History E: drive store** — local recovery when everything else fails
