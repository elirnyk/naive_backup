# Naive Backup

Naive Backup is a lightweight, shell-based backup utility designed for simplicity and security. It uses GPG for encryption and `tar`/`bzip2` for archiving, with support for incremental backups. It is configured via simple definition files and is ideal for backing up file lists and database dumps from cron jobs.

This project is architecture-independent and can be run on any system with a POSIX-compliant shell and the required dependencies.

## Features

- **GPG Encryption:** All backups are encrypted and signed.
- **Efficient Backups:** Creates backups only when changes are detected.
- **Incremental Backups:** Supports differential backups for content-based definitions to save space.
- **File & Content-based Backups:** Can back up lists of files or the output of scripts (e.g., database dumps).
- **Simple Configuration:** Define what to back up with simple `.lst`, `.sh`, or `.d` files.
- **Extensible:** Supports custom persistence methods for storing backups in different locations (e.g., cloud storage).

---

## How it Works: Minimizing Backups

`naive-backup` is designed to be efficient by avoiding the creation of unnecessary backup files. It uses different strategies for file-based and content-based backups.

### File-Based Backups (`files-*.lst`, `files-*.d`)

For file-based backups, the script does not simply archive the files on every run. Instead, it generates a "manifest" of all files that would be included in the backup. This manifest includes:

- File paths
- Permissions (`%A`)
- Owner/Group (`%U`/`%G`)
- File type (`%F`)

A checksum (MD5) is calculated for this entire manifest. The script creates a new backup `.tar.gz` file **only if the checksum of the new manifest is different from the checksum of the previous run**.

This means a new backup is created only when:

- A file's content has changed (which changes its MD5 checksum).
- A file's permissions, owner, or group have been modified.
- A file is added to or removed from a directory being backed up.

This checksum approach is highly efficient for large sets of files that change infrequently.

### Content-Based Backups (`content-*.sh`)

Content-based backups are designed for script outputs, like database dumps. This is where the incremental backup logic comes into play.

1. **Full Backup (Base):** When a backup is run for the first time, or when the script determines a new full backup is needed, it executes your `.sh` script and stores the entire output as a compressed "full" backup (`-full-*.bz2.gpg`).

2. **Change Detection:** On subsequent runs, it re-executes your script and compares the new output with the most recent *full* backup and the most recent *base* (which could be full or incremental).

3. **Incremental Backup (Diff):** If changes are detected, instead of storing the entire new output, the script creates a `diff` between the last base version and the new output. Only this `diff` is compressed and stored as an "incremental" backup (`-inc-*.diff.bz2.gpg`). This results in a much smaller file if the changes are minor.

4. **New Full Backup Trigger:** A new full backup is created automatically if the size of the `diff` exceeds a certain percentage of the full backup's size (default is 15%, configurable via `SIZE_THRESHOLD`). This prevents a long chain of large diffs from becoming inefficient to restore.

---

## Installation

You can install Naive Backup using the official APT or OPKG repositories, which are automatically updated on every release.

### Public GPG Key

First, you need to add the repository's public GPG key to your system to verify the packages.

[**Download the Public GPG Key here**](./public.key)

### For Debian / Ubuntu (APT)

1. **Add the GPG Key:**
   
   ```bash
   curl -s "https://elirnyk.github.io/naive_backup/public.key" | gpg --dearmor | sudo tee /usr/share/keyrings/naive-backup-archive-keyring.gpg >/dev/null
   ```

2. **Add the Repository:**
   
   ```bash
   echo "deb [signed-by=/usr/share/keyrings/naive-backup-archive-keyring.gpg] https://elienyk.github.io/naive_backup/apt/ ./" | sudo tee /etc/apt/sources.list.d/naive-backup.list
   ```

3. **Install the Package:**
   
   ```bash
   sudo apt update
   sudo apt install naive-backup
   ```

### For OpenWrt (OPKG)

1. **Add the repository signing key:**
   
   ```bash
   (T=$(mktemp) && trap "rm -f $T" EXIT && curl -sL https://elirnyk.github.io/naive_backup/opkg/repokey.pub -o $T && opkg-key add $T)
   ```

2. **Add the Repository:** Add the following line to `/etc/opkg/customfeeds.conf`:
   
   ```
   src/gz naive_backup https://elirnyk.github.io/naive_backup/opkg
   ```

3. **Install the Package:**
   
   ```bash
   opkg update
   opkg install naive-backup
   ```

   > **Note:** If you encounter signature errors, disable by adding `#` before `option check_signature` in `/etc/opkg/`

### OpenWrt Dependencies

The package requires only 3 external packages beyond busybox:

- **bzip2**: Used for compressing incremental content-based backups
- **coreutils-stat**: GNU stat with format support (`%A %U %G %F`) used in checksums
- **gnupg**: Encryption and signing of backup archives

All other utilities (sed, sort, find, tar, md5sum) are provided by busybox.

## Usage

The `naive-backup` script is run with a configuration directory. By default, it uses `/etc/naivebackup`.

```bash
naive-backup [-c /path/to/your/confdir] [<definition_to_run>]
```

### Configuration

1. **Settings (`/etc/naivebackup/settings.conf`):**
   This file contains global settings for the backup process.
   
   ```bash
   # (Required) The GPG key ID or email address of the recipient.
   ENCRYPT_RECIPIENT="your-gpg-email@example.com"
   
   # (Required for default persister) The directory to store backup files.
   BACKUPDIR="/var/backups/naive"
   
   # (Optional) A prefix for all backup files.
   # PREFIX="my-server-backup"
   
   # (Optional) The percentage difference at which to create a new full backup.
   # SIZE_THRESHOLD=15
   ```

2. **Backup Definitions:**
   Create files in your configuration directory to define what to back up. The filename determines the type of backup.
   
   - **`files-myfiles.lst`**: Backs up a list of files and directories specified in this file (one per line). `tar` will archive entire directories listed.
   - **`files-myscripts.d`**: A directory containing `.lst` or `.sh` files to be processed.
   - **`content-mydatabase.sh`**: An executable script that outputs content to be backed up (e.g., `mysqldump`). An incremental backup will be created if the content changes.

### Example

To back up your home directory's documents and a PostgreSQL database:

1. **Create `/etc/naivebackup/files-docs.lst`:**
   
   ```
   /home/user/Documents
   /home/user/spreadsheets
   ```

2. **Create `/etc/naivebackup/content-pg_backup.sh` (and make it executable):**
   
   ```bash
   #!/bin/sh
   pg_dump -U myuser mydatabase
   ```

3. **Run the backup:**
   
   ```bash
   sudo naive-backup
   ```
   
   This will create encrypted tarballs in your `BACKUPDIR` for the `docs` and `pg_backup` definitions.
