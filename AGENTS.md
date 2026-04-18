# AGENTS.md - Naive Backup

## Quick Start

```bash
# Run locally for testing (avoids /etc/naivebackup)
./naive_backup.sh -c ./test_conf

# Lint (ShellCheck is the only CI check)
shellcheck naive_backup.sh

# Build Debian package
dpkg-buildpackage -us -uc -b

# Install OpenWrt (use raw.githubusercontent.com, not jeka.github.io)
curl -LO https://raw.githubusercontent.com/elirnyk/naive_backup/gh-pages/opkg/naive-backup_<ver>_all.ipk
opkg install naive-backup_<ver>_all.ipk
```

## Key Facts

- **Script**: `naive_backup.sh` - POSIX-compliant sh (not bash)
- **Config dir**: `/etc/naivebackup/` (default) or `-c <path>` override
- **Settings**: `settings.conf` - requires `ENCRYPT_RECIPIENT`, `BACKUPDIR`
- **GPG**: All backups encrypted and signed; `ENCRYPT_RECIPIENT` is comma-separated list

## Definition Naming

| Pattern | Type | Example |
|---------|------|---------|
| `files-<name>.lst` | File list | `files-docs.lst` |
| `files-<name>.d` | Directory of snippets | `files-myscripts.d` |
| `content-<name>.sh` | Script output (incremental) | `content-db.sh` |

Numeric prefixes allowed: `10-files-foo.lst`, `20-content-bar.sh` (processed in order).

## Backup Logic

**Files-based**: Manifest checksum (MD5 of paths + perms + owner). New backup only if manifest changes.

**Content-based**: Script output. Full backup on first run. Subsequent runs create diffs. New full backup if diff > `SIZE_THRESHOLD%` (default 15%). Uses bzip2 + gpg.

## Common Pitfalls

- `CONTENT_WORK_DIR` must be owned by current user with `0700` permissions
- Filenames with spaces/newlines: use `find -print0` + `read -r -d ''`
- ShellCheck warnings in `naive_backup.sh` are annotated with `shellcheck disable=...` - don't remove without checking
- Avoid bashisms: no `[[ ]]`, no `local`, no process substitution `<()` - use `find ... | while read` with here-docs for variable scope

## Reference

- `README.md`: Usage and architecture
- `GEMINI.md`: Technical context and conventions
- `naive_backup.sh`: Source of truth