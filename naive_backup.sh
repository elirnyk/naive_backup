#!/bin/bash

trap cleanup EXIT

cleanup() {
    [[ -f "$TMP_FILE1" ]] && rm -f "$TMP_FILE1" && echo "[-]--> $TMP_FILE1"
    [[ -f "$TMP_FILE2" ]] && rm -f "$TMP_FILE2" && echo "[-]--> $TMP_FILE2"
}

persist_check() {

    if [ -z "$BACKUPDIR" ] || [ ! -d "$BACKUPDIR" ]; then
        echo "BACKUPDIR config parameter is required and directory specified should be writeable" >&2
        return 1
    fi
}

persist_file() {
    cat > "$BACKUPDIR/$1"
}

get_file() {
    if [ -f "$BACKUPDIR/$1" ]; then
        cat "$BACKUPDIR/$1"
    fi
}

check_content_work_dir() {
    if [ -z "$CONTENT_WORK_DIR" ]; then
        echo "CONTENT_WORK_DIR is required parameter." >&2
        return 1;
    elif [ ! -d "$CONTENT_WORK_DIR" ]; then
        echo "'$CONTENT_WORK_DIR' expected to be a directory." >&2
        return 1;
    elif [ ! -O "$CONTENT_WORK_DIR" ]; then
        echo "'$CONTENT_WORK_DIR' should be owned by '$(whoami)' user." >&2
        return 1;
    elif [ "$(stat -L -c "0%a" "$CONTENT_WORK_DIR")" != "0700" ]; then
        echo "'$CONTENT_WORK_DIR' should have 0700 permissions set." >&2
        return 1
    fi
}

process_files_directory() {
    if [ ! -d "$1" ]; then
        echo "$1 is expected to be a directory." >&2
        return 1
    fi
    echo "[d]--> $1" >&3
    find "$1" -maxdepth 1 -regex ".*\(lst\|sh\)" | while read -r SNIP; do
    TYPE=$(echo "$SNIP" | sed -n -e "s/.*\(lst\|sh\)/\1/p")
        if [ "$TYPE" = "sh" ]; then
            process_files_executable "$SNIP" "$2" "--"
        else
            process_files_plain "$SNIP" "$2" "--"
        fi
    done
}

process_files_executable() {
    if [ ! -x "$1" ]; then
        echo "$1 is expected to be a executable file." >&2
        return 1
    fi
    echo "[x]$3--> $1" >&3
    
    "$1" 
    
    if [ $? != "0" ]; then
        echo "Failed to run $1" >&2 
        return 1
    fi
}

process_files_plain() {
    if [ ! -f "$1" ] || [ -x "$1" ]; then
        echo "$1 is expected to be a regular file." >&2
        return 1
    fi

    echo "[*]$3--> $1" >&3
    local HAS_ERRORS=false
    cat "$1" | while read -r LINE ; do
        [ -z "$LINE" ] || find "$LINE" -follow -type f || HAS_ERRORS=true
        if [ "$HAS_ERRORS" = true ]; then
            false
        fi
    done
    # shellcheck disable=SC2181
    if [ $? != "0" ]; then
        return 1
    fi
}

process_files_by_type() {
    if [ "$3" = "d" ]; then
        process_files_directory "$1" "$2"
    elif [ "$3" = "sh" ]; then
        process_files_executable "$1" "$2"
    elif [ "$3" = "lst" ]; then
        process_files_plain "$1" "$2"
    fi
}

checksum_files() {
    while read -r LINE; do
	    if ! ([ -f "$LINE" ] && md5sum "$LINE" ) ; then
	    echo "$LINE is not regular file" >&2
	    return 1
	fi
        stat -c "%A %U %G %F %N" "$LINE" || return 1
    done	
}

process_files() {
    FILES=$(process_files_by_type "$1" "$2" "$3" | sort) || return 1
    if [ -z "$FILES" ]; then
        echo "[$2]--> empty input." >&2
        return 1
    else
	LINES=$(echo "$FILES" | wc -l)
	echo "[$2]--> $LINES files to process" >&2
    fi
    CHECKSUM=$(echo "$FILES" | checksum_files | md5sum | cut -f 1 -d " ") || return 1
    echo "[$2] NEW CHECKSUM: $CHECKSUM" >&3
    CCHECKSUM=$($GET_FILE "$PREFIX-$2.checksum") || return 1
    echo "[$2] OLD CHECKSUM: ${CCHECKSUM:=<empty>}" >&3

    if [ "$CCHECKSUM" != "$CHECKSUM" ]; then
        echo "[$2]--> creating new backup file." >&3
        echo "$FILES" | sed -e "s/^\///" | (cd /; tar  --verbatim-files-from -T - -czf - ) | encrypt_and_sign | $PERSIST_FILE "$PREFIX-$2-$BAKDATE.tar.gz.gpg" || return 1
        echo "$CHECKSUM" | $PERSIST_FILE "$PREFIX-$2.checksum"
    else
        echo "[$2]--> skipping..." >&3
    fi
}

process_content_executable() {
    check_content_work_dir || return 1

    process_files_executable "$1" "$2"
}

process_content() {
    if [ "$3" = "sh" ]; then
        process_content_executable "$1" "$2" > "$TMP_FILE1" || return 1
        
        LASTBASE=$(find "$CONTENT_WORK_DIR" -name "$2-full-*" -or -name "$2-base-*" | \
	    sed -e "s/.*$2-\(\(full\|base\)-\(.*\)\).sql.bz2/\1/" | sort -k 1.6r | head -1)
	LASTFULL=$(find "$CONTENT_WORK_DIR" -name "$2-full-*" | sed -e "s/.*$2-full-\(.*\).sql.bz2/\1/" | sort -r | head -1)


        [ "$LASTBASE" ] && echo "[$2]--> Last base: $LASTBASE" || echo "[$2]--> No base version" >&3
        [ "$LASTFULL" ] && echo "[$2]--> Last full: full-$LASTFULL" || echo "[$2]--> No full version" >&3
        
        if [ "$LASTBASE" ] && [ "$LASTFULL" ]; then
	    diff -r <(bunzip2 -c "$CONTENT_WORK_DIR/$2-$LASTBASE.sql.bz2") <(cat "$TMP_FILE1") > "$TMP_FILE2"
	    DIFFLINES=$(wc -l < "$TMP_FILE2")
            echo "[$2]--> Changed lines/base: $DIFFLINES" >&3

            if [ "$DIFFLINES" -gt 0 ] && [ "$LASTBASE" != "full-$LASTFULL" ]; then
                diff -r <(bunzip2 -c "$CONTENT_WORK_DIR/$2-full-$LASTFULL.sql.bz2") <(cat "$TMP_FILE1") > "$TMP_FILE2"
		DIFFLINES=$(wc -l < "$TMP_FILE2")
                echo "[$2]--> Changed lines/full: $DIFFLINES" >&3
            fi
	    DIFFSIZE=$(wc -c < "$TMP_FILE2")
	    BASESIZE=$(wc -c < "$TMP_FILE1")
	    SIZEDIFF=$(( DIFFSIZE * 100 / BASESIZE ))
            TOO_BIG="no"; [ "$SIZEDIFF" -gt "$SIZE_THRESHOLD" ] && TOO_BIG="yes"

            echo "[$2]--> Size (full): $BASESIZE" >&3
            echo "[$2]--> Size (diff): $DIFFSIZE" >&3
            echo "[$2]--> Diff size percentage: $SIZEDIFF" >&3
            echo "[$2]--> Too big? - $TOO_BIG" >&3
        fi

        if [ "$BASESIZE" = "0" ] || [ "$TOO_BIG" = "yes" ] || [ -z "$LASTBASE" ] || [ -z "$LASTFULL" ]; then
            
            OLDFILEFULL="$CONTENT_WORK_DIR/$2-full-$LASTFULL.sql.bz2"
            OLDFILEBASE="$CONTENT_WORK_DIR/$2-$LASTBASE.sql.bz2"

	    # shellcheck disable=SC2015
            [ "$LASTFULL" ] && [ -f "$OLDFILEFULL" ] && mv "$OLDFILEFULL" "$OLDFILEFULL.bak" || true
            # shellcheck disable=SC2015
	    [ "$LASTBASE" ] && [ -f "$OLDFILEBASE" ] && mv "$OLDFILEBASE" "$OLDFILEBASE.bak" || true
            
            (umask 077; bzip2 < "$TMP_FILE1" > "$CONTENT_WORK_DIR/$2-full-$BAKDATE.sql.bz2") || return 1
            
            encrypt_and_sign < "$CONTENT_WORK_DIR/$2-full-$BAKDATE.sql.bz2" | $PERSIST_FILE "$PREFIX-$2-full-$BAKDATE.bz2.gpg" || return 1

	    # shellcheck disable=SC2015
            [ "$LASTFULL" ] && rm -f "$OLDFILEFULL.bak" || true
            # shellcheck disable=SC2015
	    [ "$LASTBASE" ] && rm -f "$OLDFILEBASE.bak" || true
        
        elif [ "$DIFFLINES" -gt 0 ]; then

            BASETYPE=${LASTBASE/-*/}

            OLDFILEBASE="$CONTENT_WORK_DIR/$2-$LASTBASE.sql.bz2"
            # shellcheck disable=SC2015
	    [ "$BASETYPE" = "base" ] && [ -f "$OLDFILEBASE" ] && mv "$OLDFILEBASE" "$OLDFILEBASE.bak" || true

            (umask 077; bzip2 <"$TMP_FILE1" > "$CONTENT_WORK_DIR/$2-base-$BAKDATE.sql.bz2") || return 1

            bzip2 < "$TMP_FILE2" | encrypt_and_sign | $PERSIST_FILE "$PREFIX-$2-inc-$LASTFULL-$BAKDATE.diff.bz2.gpg" || return 1

            # shellcheck disable=SC2015
	    [ "$BASETYPE" = "base" ] && rm -f "$OLDFILEBASE.bak" || true
        
        else
            echo "[$2]--> No changes detected." >&3
        fi

    else
	echo "$1 ignored - only excutable is allowed for content definition." >&2
	return 1;
    fi
}

process_single_definition() {
    if [ "$3" = "files" ]; then
        process_files "$1" "$2" "$4"
    else
        process_content "$1" "$2" "$4"
    fi
}

process_and_store_single_definition() {
    process_single_definition "$1" "$2" "$3" "$4" 3>&1
}

encrypt_and_sign() {
    gpg --batch --sign --encrypt $(echo "$ENCRYPT_RECIPIENT" | tr "," "\n" | sed -e 's/^/--recipient /')
}

usage() {
    echo "Usage: $0 [-c <configuration directory] [<definition to run>]" 1>&2; 
    exit 1;
}

while getopts ":c:" o; do
    case "${o}" in
        c)
            CONFDIR=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

CONFDIR=${CONFDIR:="/etc/naivebackup"}

if [ ! -d "$CONFDIR" ]; then
    echo "$CONFDIR is not valid directory." >&2
    usage
fi

TO_FIND=${1:-'[^/]*'}

CONF_REGEX_FIND=".*/\([0-9]+-\)*\(content\|files\)-\($TO_FIND\)\.\(lst\|d\|sh\)"
CONF_REGEX_SED=".*/\([0-9]\+-\)*\(content\|files\)-\($TO_FIND\)\.\(lst\|d\|sh\)"

if [ -f "$CONFDIR/settings.conf" ]; then
    # shellcheck disable=SC1090
    . "$CONFDIR/settings.conf"
fi

SIZE_THRESHOLD=${SIZE_THRESHOLD:=15}

PREFIX=${PREFIX:=backup-$(cat /proc/sys/kernel/hostname)}

BAKDATE=$(date +%F)

set -o pipefail
! type persist_file_custom >/dev/null 2>&1; HAS_CUSTOM_PERSIST_FILE=$?
! type get_file_custom >/dev/null 2>&1; HAS_CUSTOM_GET_FILE=$?

if [ $HAS_CUSTOM_PERSIST_FILE -ne $HAS_CUSTOM_GET_FILE ]; then
    echo "You should specify both 'persist_file_custom' and 'get_file_custom'" >&2
    exit 2
fi

if [ $HAS_CUSTOM_PERSIST_FILE -ne 0 ]; then
    PERSIST_FILE="persist_file_custom"
    GET_FILE="get_file_custom"
    ! type persister_check_custom >/dev/null 2>&1 || persister_check_custom || exit 2
else	
    PERSIST_FILE="persist_file"
    GET_FILE="get_file"
    persist_check || exit 2
fi

if [ -z "$ENCRYPT_RECIPIENT" ]; then
    echo "ENCRYPT_RECIPIENT is required parameter." >&2
    exit 2
fi

CONFIGS=$(find $CONFDIR -maxdepth 1 -regex "$CONF_REGEX_FIND" | sort)

DUPES=$(echo "$CONFIGS" | sed -n -e "s#$CONF_REGEX_SED#\3#p" | sort | uniq --repeated)

HAS_ERRORS=false

if [ -z "$CONFIGS" ]; then
    echo "Nothing to backup" >&2
    exit 2
fi


TMP_FILE1=$(mktemp -t naive_backup.XXXXXXXX) || exit 2
TMP_FILE2=$(mktemp -t naive_backup.XXXXXXXX) || exit 2

echo "$CONFIGS" | while IFS= read -r CNF; do
    NAME=$(echo "$CNF" | sed -n -e "s#$CONF_REGEX_SED#\3#p")
    IS_DUPE=$(echo "$DUPES" | grep "$NAME")
    if [ -n "$IS_DUPE" ]; then
        echo "$CNF is ignored due to duplicate definition '$NAME'" >&2
	HAS_ERRORS=true
    else
	EXT=$(echo "$CNF" | sed -n -e "s#$CONF_REGEX_SED#\4#p")
	TYPE=$(echo "$CNF" | sed -n -e "s#$CONF_REGEX_SED#\2#p")
        echo "[$NAME]--> ..."
        if process_and_store_single_definition "$CNF" "$NAME" "$TYPE" "$EXT" 3>&1; then
            echo "[$NAME]--> SUCCESS"
        else
            echo "[$NAME]--> FAILURE"
            HAS_ERRORS=true
        fi
    fi
    if [ "$HAS_ERRORS" = true ]; then
        false
    fi

done

