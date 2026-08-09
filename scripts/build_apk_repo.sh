#!/bin/sh
#
# Build an apk package and a signed apk repository index for OpenWrt.
#
# Mirrors the way OpenWrt's own build system creates packages
# (see include/package-pack.mk) using apk-tools 3.x (`apk mkpkg`,
# `apk adbsign`, `apk mkndx`) and an EC P-256 signing key.
#
# Requirements: apk-tools 3.x and openssl in PATH.
#
# Usage:
#   build_apk_repo.sh <version> <sign-key> <outdir>
#
#   <version>   Version tag, e.g. "0.8.0" or "v0.8.0" or "0.8.0-r1".
#               A missing "-r<rev>" suffix gets "-r0" appended.
#   <sign-key>  Path to the EC P-256 private key (PEM) used to sign
#               the package and the index.
#   <outdir>    Directory where the .apk, packages.adb, public key
#               and checksum files are written.

set -eu

NAME="naive-backup"
MAINTAINER="Gemini CLI <gemini-cli@google.com>"
URL="https://github.com/elirnyk/naive_backup"
DEPENDS="tar bzip2 coreutils-stat gnupg"
DESCRIPTION="A simple shell-based backup script."

usage() {
    echo "usage: $0 <version> <sign-key> <outdir>" >&2
    exit 2
}

[ "$#" -eq 3 ] || usage

VERSION="$1"
SIGN_KEY="$2"
OUTDIR="$3"

# apk runs below in a subshell that cd's into a temp work dir, so make
# relative paths absolute now (against the caller's cwd) before we leave it.
case "$SIGN_KEY" in /*) ;; *) SIGN_KEY="$PWD/$SIGN_KEY" ;; esac
case "$OUTDIR" in /*) ;; *) OUTDIR="$PWD/$OUTDIR" ;; esac

VERSION="${VERSION#v}"
case "$VERSION" in
    *-r[0-9]*) ;;
    *) VERSION="${VERSION}-r0" ;;
esac

command -v openssl >/dev/null 2>&1 || {
    echo "ERROR: openssl is required" >&2
    exit 1
}

command -v apk >/dev/null 2>&1 || {
    echo "ERROR: apk-tools 3.x (apk) is required" >&2
    exit 1
}

APK_MAJOR="$(apk --version 2>/dev/null | sed -n 's/^apk-tools \([0-9]*\)\..*/\1/p')"
[ "${APK_MAJOR:-0}" -ge 3 ] || {
    echo "ERROR: apk-tools 3.x required, found: $(apk --version)" >&2
    exit 1
}

[ -f "$SIGN_KEY" ] || {
    echo "ERROR: signing key not found: $SIGN_KEY" >&2
    exit 1
}

ARCHIVE="${NAME}-${VERSION}.apk"

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
KEYS_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR" "$KEYS_DIR"' EXIT INT TERM

# --------------------------------------------------------------------------
# Stage the package payload (same layout as the old .ipk package).
# --------------------------------------------------------------------------
STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE/usr/bin"
mkdir -p "$STAGE/etc/naivebackup"

cp "$ROOT/naive-backup" "$STAGE/usr/bin/naive-backup"
chmod 0755 "$STAGE/usr/bin/naive-backup"

cp "$ROOT/etc/openwrt/settings.conf" "$STAGE/etc/naivebackup/settings.conf"
cp "$ROOT/etc/openwrt/files-config.sh" "$STAGE/etc/naivebackup/files-config.sh"
chmod 0755 "$STAGE/etc/naivebackup/files-config.sh"

# --------------------------------------------------------------------------
# Build the package.
# --------------------------------------------------------------------------
(
    cd "$WORK_DIR"

    mkdir -p "$OUTDIR"

    SOURCE_DATE_EPOCH=0 apk mkpkg \
        --info "name:${NAME}" \
        --info "version:${VERSION}" \
        --info "arch:noarch" \
        --info "description:${DESCRIPTION}" \
        --info "maintainer:${MAINTAINER}" \
        --info "url:${URL}" \
        --info "depends:${DEPENDS}" \
        --files "$STAGE" \
        --output "$ARCHIVE"

    # ----------------------------------------------------------------------
    # Sign the package itself, then generate the signed repository index.
    # ----------------------------------------------------------------------
    apk adbsign --allow-untrusted --reset-signatures \
        --sign-key "$SIGN_KEY" "$ARCHIVE"

    apk mkndx --allow-untrusted \
        --sign-key "$SIGN_KEY" --output packages.adb "$ARCHIVE"

    # ----------------------------------------------------------------------
    # Derive and verify the public key.
    # ----------------------------------------------------------------------
    openssl ec -in "$SIGN_KEY" -pubout -out naive-backup.pem 2>/dev/null

    cp naive-backup.pem "$KEYS_DIR/naive-backup.pem"
    apk verify --keys-dir "$KEYS_DIR" "$ARCHIVE"
    apk verify --keys-dir "$KEYS_DIR" packages.adb

    openssl pkey -pubin -in naive-backup.pem -outform DER 2>/dev/null \
        | sha256sum | awk '{print $1}' > PUBLIC_KEY_SHA256

    sha256sum ./*.apk packages.adb naive-backup.pem > SHA256SUMS

    # ----------------------------------------------------------------------
    # Move the artifacts into the output directory.
    # ----------------------------------------------------------------------
    cp -a "$ARCHIVE" packages.adb naive-backup.pem \
        PUBLIC_KEY_SHA256 SHA256SUMS "$OUTDIR/"
)

echo "Built and signed:"
ls -l "$OUTDIR"
