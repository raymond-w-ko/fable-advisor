#!/usr/bin/env bash
# Set Codex sandbox mode to danger-full-access in the top-level config.
set -eu

DRY_RUN=0
REVERT=0

usage() {
    printf '%s\n' \
        'Usage: scripts/setup-yolo-codex.sh [--dry-run] [--revert]' \
        '' \
        '  --dry-run  print the config diff without writing or backing up' \
        '  --revert   remove the top-level sandbox_mode key' >&2
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit "${2:-1}"
}

note() {
    printf '%s\n' "$1"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --revert) REVERT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; fail "unknown option: $1" 2 ;;
    esac
    shift
done

[ "$DRY_RUN" -eq 0 ] || [ "$REVERT" -eq 0 ] || \
    fail '--dry-run and --revert cannot be combined' 2

CODEX_HOME_DIR=${CODEX_HOME:-$HOME/.codex}
CONFIG="$CODEX_HOME_DIR/config.toml"
TMP=
PREHEADER=
BACKUP=

cleanup() {
    if [ -n "$TMP" ] && [ -f "$TMP" ]; then
        rm -f -- "$TMP"
    fi
    if [ -n "$PREHEADER" ] && [ -f "$PREHEADER" ]; then
        rm -f -- "$PREHEADER"
    fi
}
trap cleanup EXIT

success_note() {
    if [ "$REVERT" -eq 1 ]; then
        note "sandbox_mode = \"danger-full-access\" removed from $CONFIG (codex lanes no longer run unsandboxed on this host)"
    else
        note "sandbox_mode = \"danger-full-access\" set in $CONFIG (codex lanes now run unsandboxed on this host)"
    fi
}

has_top_level_sandbox() {
    awk '
        /^[[:space:]]*\[/ { exit }
        /^[[:space:]]*sandbox_mode[[:space:]]*=/ { found = 1; exit }
        END { if (found) exit 0; exit 1 }
    ' "$CONFIG"
}

if [ -e "$CONFIG" ] && [ ! -f "$CONFIG" ]; then
    fail "config path is not a regular file: $CONFIG"
fi

if [ "$REVERT" -eq 1 ]; then
    if [ ! -f "$CONFIG" ]; then
        note "config: $CONFIG does not exist; nothing changed"
        success_note
        exit 0
    fi
    [ -r "$CONFIG" ] || fail "config is not readable: $CONFIG"
    if ! has_top_level_sandbox; then
        note "config: no top-level sandbox_mode in $CONFIG; nothing changed"
        success_note
        exit 0
    fi
fi

if ! TMP=$(mktemp "${TMPDIR:-/tmp}/setup-yolo-codex.XXXXXX"); then
    fail 'could not create temporary file'
fi

if [ -f "$CONFIG" ]; then
    [ -r "$CONFIG" ] || fail "config is not readable: $CONFIG"
    if ! awk -v revert="$REVERT" \
        -v desired='sandbox_mode = "danger-full-access"' '
        function emit_pre(    i, line) {
            for (i = 1; i <= pre_count; i++) {
                line = pre[i]
                if (line ~ /^[[:space:]]*sandbox_mode[[:space:]]*=/) {
                    if (!revert) print desired
                } else {
                    print line
                }
            }
        }

        {
            if (!seen_header && $0 ~ /^[[:space:]]*\[/) {
                emit_pre()
                if (!revert && !found) print desired
                seen_header = 1
                print
                next
            }

            if (!seen_header) {
                pre[++pre_count] = $0
                if ($0 ~ /^[[:space:]]*sandbox_mode[[:space:]]*=/) found = 1
                next
            }

            print
        }

        END {
            if (!seen_header) {
                emit_pre()
                if (!revert && !found) print desired
            }
        }
    ' "$CONFIG" > "$TMP"; then
        fail "could not transform config: $CONFIG"
    fi
else
    printf '%s\n' 'sandbox_mode = "danger-full-access"' > "$TMP"
fi

show_diff() {
    DIFF_STATUS=0
    if [ -f "$CONFIG" ]; then
        if diff -u "$CONFIG" "$TMP"; then
            DIFF_STATUS=0
        else
            DIFF_STATUS=$?
        fi
    else
        if diff -u /dev/null "$TMP"; then
            DIFF_STATUS=0
        else
            DIFF_STATUS=$?
        fi
    fi
    [ "$DIFF_STATUS" -le 1 ] || fail "could not produce diff for $CONFIG"
}

if [ "$DRY_RUN" -eq 1 ]; then
    show_diff
    if [ "$DIFF_STATUS" -eq 0 ]; then
        note "dry-run: nothing changed in $CONFIG"
    else
        note "dry-run: no changes written to $CONFIG"
    fi
    exit 0
fi

if [ -f "$CONFIG" ]; then
    if diff -q "$CONFIG" "$TMP" >/dev/null 2>&1; then
        note "config: nothing changed in $CONFIG"
        success_note
        exit 0
    else
        DIFF_STATUS=$?
        [ "$DIFF_STATUS" -eq 1 ] || fail "could not compare config: $CONFIG"
    fi
fi

if ! mkdir -p "$CODEX_HOME_DIR"; then
    fail "could not create Codex home: $CODEX_HOME_DIR"
fi

if [ -f "$CONFIG" ]; then
    BACKUP="$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    BACKUP_BASE=$BACKUP
    BACKUP_NUMBER=1
    while [ -e "$BACKUP" ]; do
        BACKUP="$BACKUP_BASE.$BACKUP_NUMBER"
        BACKUP_NUMBER=$((BACKUP_NUMBER + 1))
    done
    if ! cp -- "$CONFIG" "$BACKUP"; then
        fail "could not create config backup: $BACKUP"
    fi
    note "config: backup at $BACKUP"
fi

if ! mv -- "$TMP" "$CONFIG"; then
    fail "could not write config: $CONFIG (backup: ${BACKUP:-none})"
fi
TMP=
note "config: wrote $CONFIG"

restore_after_validation_failure() {
    if [ -n "$BACKUP" ]; then
        if cp -- "$BACKUP" "$CONFIG"; then
            fail "config: TOML validation failed; restored from backup at $BACKUP"
        else
            fail "config: TOML validation failed and restore failed; backup at $BACKUP"
        fi
    fi
    rm -f -- "$CONFIG" || true
    fail "config: TOML validation failed; no backup available for $CONFIG"
}

validate_with_python() {
    if [ "$REVERT" -eq 1 ]; then
        python3 - "$CONFIG" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    data = tomllib.load(config_file)

if "sandbox_mode" in data:
    raise SystemExit("top-level sandbox_mode still exists")
PY
    else
        python3 - "$CONFIG" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    data = tomllib.load(config_file)

if data.get("sandbox_mode") != "danger-full-access":
    raise SystemExit("sandbox_mode has unexpected value")
PY
    fi
}

if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' >/dev/null 2>&1; then
    if ! validate_with_python; then
        restore_after_validation_failure
    fi
else
    note 'verify: TOML validation skipped (python3/tomllib unavailable)'
    if ! PREHEADER=$(mktemp "${TMPDIR:-/tmp}/setup-yolo-codex-preheader.XXXXXX"); then
        restore_after_validation_failure
    fi
    if ! awk '/^[[:space:]]*\[/ { exit } { print }' "$CONFIG" > "$PREHEADER"; then
        restore_after_validation_failure
    fi
    EXPECTED_COUNT=1
    [ "$REVERT" -eq 0 ] || EXPECTED_COUNT=0
    COUNT=$(grep -c '^[[:space:]]*sandbox_mode[[:space:]]*=' "$PREHEADER" || true)
    rm -f -- "$PREHEADER"
    PREHEADER=
    [ "$COUNT" -eq "$EXPECTED_COUNT" ] || \
        restore_after_validation_failure
fi

success_note
