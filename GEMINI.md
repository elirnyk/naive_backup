# Naive Backup: Project Context

This file serves as a foundational guide for AI agents and developers working on the `naive-backup` project.

## Project Overview

`naive-backup` is a lightweight, shell-based backup utility designed for simplicity, security, and efficiency. It is intended for use in environments where minimal dependencies are preferred (e.g., servers, OpenWrt routers).

-   **Main Technology:** Bash (currently transitioning to POSIX-compliant Shell).
-   **Security:** Uses GPG for asymmetric encryption and signing of all backup archives.
-   **Storage Logic:**
    -   **File-Based:** Uses manifest-based checksums to skip backups if no file changes (content, permissions, or ownership) are detected.
    -   **Content-Based:** Executes scripts (e.g., database dumps) and performs incremental `diff` backups to minimize storage usage.
-   **Architecture:** POSIX-compliant infrastructure.
-   **Packaging:** Supports Debian (APT) and OpenWrt (OPKG).

## Core Components

-   `naive-backup`: The main execution script.
-   `/etc/naivebackup/settings.conf`: Global configuration (GPG recipients, backup directory, etc.).
-   **Definitions:**
    -   `files-*.lst`: Plain text list of files/directories to back up.
    -   `files-*.d`: Directory containing backup snippets.
    -   `content-*.sh`: Executable scripts whose output is backed up incrementally.

## Building and Running

### Development & Linting
The project uses **ShellCheck** for static analysis.
```bash
# Run shellcheck on the main script
shellcheck naive-backup
```

### Testing
There is currently no automated test suite, but implementation of **BATS (Bash Automated Testing System)** is planned (see `TODO`).

### Local Execution
To run the script locally for testing without modifying system files:
```bash
# Create a local config directory
mkdir -p ./test_conf
# Run with custom config path
./naive-backup -c ./test_conf
```

### Packaging
The project is packaged for Debian using `debhelper`.
```bash
# Build the Debian package
dpkg-buildpackage -us -uc -b
```

## Development Conventions

1.  **POSIX Compatibility:** A major goal is to migrate from `#!/bin/bash` to `#!/bin/sh`. Avoid "bashisms" like `[[ ]]`, `local` (unless handled carefully), and process substitution `<()`. Use `command -v` instead of `type`.
2.  **Error Handling:** Use `set -o pipefail` (where available) and ensure exit codes are propagated through pipes and subshells. Avoid the "subshell variable loss" pitfall by using process substitution or temporary files for `while read` loops.
3.  **Filenames:** Robustly handle filenames containing spaces or newlines using `find -print0` and `read -r -d ''`.
4.  **Temporary Files:** Always use `mktemp` and ensure cleanup via `trap '...' EXIT`.
5.  **Security:** Never hardcode secrets. Ensure backup work directories (like `CONTENT_WORK_DIR`) have strict `0700` permissions.
6.  **GPG:** Always sign and encrypt backups. The `ENCRYPT_RECIPIENT` variable should be a comma-separated list of GPG IDs/emails.

## Roadmap & Known Issues (See `TODO` and `review.md`)

-   Fix subshell bugs where `HAS_ERRORS` state is lost.
-   Implement BATS-based unit testing.
-   Complete the transition to POSIX `sh`.
-   Migrate from `md5sum` to `sha256sum`.
