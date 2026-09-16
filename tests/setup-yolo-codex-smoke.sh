#!/usr/bin/env bash
set -eu

SCRIPT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/setup-yolo-codex.sh
ROOT=
FAILURES=0

cleanup() {
    if [ -n "$ROOT" ] && [ -d "$ROOT" ]; then
        rm -rf -- "$ROOT"
    fi
}
trap cleanup EXIT

check() {
    local number=$1 description=$2
    shift 2
    if "$@"; then
        printf 'ok %s %s\n' "$number" "$description"
    else
        printf 'FAIL %s %s\n' "$number" "$description"
        FAILURES=$((FAILURES + 1))
    fi
}

skip() {
    printf 'ok %s %s # SKIP %s\n' "$1" "$2" "$3"
}

count_exact() {
    awk -v expected="$1" '$0 == expected { count++ } END { print count + 0 }' "$2"
}

count_backups() {
    local directory=$1 backup count=0
    for backup in "$directory"/config.toml.bak.*; do
        if [ -f "$backup" ]; then
            count=$((count + 1))
        fi
    done
    printf '%s\n' "$count"
}

backup_list() {
    local directory=$1 backup
    for backup in "$directory"/config.toml.bak.*; do
        if [ -f "$backup" ]; then
            printf '%s\n' "$backup"
        fi
    done
}

check_fresh_config() {
    [ "$(sed -n '6p' "$FRESH_CONFIG")" = 'sandbox_mode = "danger-full-access"' ] &&
        [ "$(sed -n '7p' "$FRESH_CONFIG")" = '[features]' ] &&
        [ "$(count_exact 'sandbox_mode = "danger-full-access"' "$FRESH_CONFIG")" -eq 1 ] &&
        [ "$(count_exact 'sandbox_mode = "read-only"' "$FRESH_CONFIG")" -eq 1 ]
}

check_existing_config() {
    [ "$(sed -n '2p' "$EXISTING_CONFIG")" = 'sandbox_mode = "danger-full-access"' ] &&
        [ "$(sed -n '4p' "$EXISTING_CONFIG")" = '[features]' ] &&
        [ "$(count_exact 'sandbox_mode = "danger-full-access"' "$EXISTING_CONFIG")" -eq 1 ] &&
        [ "$(count_exact 'sandbox_mode = "read-only"' "$EXISTING_CONFIG")" -eq 1 ]
}

check_second_run() {
    diff -q "$FRESH_BEFORE_SECOND" "$FRESH_CONFIG" >/dev/null 2>&1 &&
        [ "$FRESH_BACKUPS_BEFORE" = "$FRESH_BACKUPS_AFTER" ] &&
        grep -q 'nothing changed' "$FRESH_SECOND_OUTPUT"
}

check_dry_run() {
    diff -q "$DRY_BEFORE" "$DRY_CONFIG" >/dev/null 2>&1 &&
        [ "$(count_backups "$DRY_HOME")" -eq 0 ] &&
        grep -q '^+sandbox_mode = "danger-full-access"$' "$DRY_OUTPUT"
}

check_revert() {
    [ "$(count_exact 'sandbox_mode = "danger-full-access"' "$FRESH_CONFIG")" -eq 0 ] &&
        [ "$(count_exact 'sandbox_mode = "read-only"' "$FRESH_CONFIG")" -eq 1 ] &&
        grep -q 'config: backup at ' "$FRESH_REVERT_OUTPUT"
}

check_missing_config() {
    [ -f "$MISSING_CONFIG" ] &&
        [ "$(count_exact 'sandbox_mode = "danger-full-access"' "$MISSING_CONFIG")" -eq 1 ] &&
        [ "$(wc -l < "$MISSING_CONFIG" | tr -d '[:space:]')" -eq 1 ] &&
        [ "$(count_backups "$MISSING_HOME")" -eq 0 ]
}

check_no_header_config() {
    awk -v expected='sandbox_mode = "danger-full-access"' '
        /^[[:space:]]*\[/ { header = 1 }
        END { if (header || $0 != expected) exit 1 }
    ' "$NO_HEADER_CONFIG" &&
        [ "$(count_exact 'sandbox_mode = "danger-full-access"' "$NO_HEADER_CONFIG")" -eq 1 ]
}

check_multiline_array_position() {
    awk -v expected='sandbox_mode = "danger-full-access"' '
        $0 == "notify = [" { in_array = 1; seen_array = 1; next }
        in_array && $0 == expected { bad = 1 }
        in_array && $0 == "]" { in_array = 0; closed_array = 1 }
        END { exit (!seen_array || !closed_array || in_array || bad) }
    ' "$MULTILINE_CONFIG" &&
        [ "$(count_exact 'sandbox_mode = "danger-full-access"' "$MULTILINE_CONFIG")" -eq 1 ]
}

check_multiline_array_toml() {
    python3 - "$MULTILINE_CONFIG" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    data = tomllib.load(config_file)

assert data["notify"] == ["python3", "n.py"]
assert data["sandbox_mode"] == "danger-full-access"
assert data["features"]["a"] == 1
PY
}

check_comment_preheader() {
    [ "$(sed -n '1p' "$COMMENT_CONFIG")" = '# Keep this comment.' ] &&
        [ "$(sed -n '2p' "$COMMENT_CONFIG")" = '# Keep this one too.' ] &&
        [ "$(sed -n '3p' "$COMMENT_CONFIG")" = 'sandbox_mode = "danger-full-access"' ] &&
        [ "$(sed -n '4p' "$COMMENT_CONFIG")" = '[features]' ] &&
        [ "$(sed -n '5p' "$COMMENT_CONFIG")" = 'a = 1' ]
}

check_backup_collision() {
    [ "$COLLISION_APPLY_RC" -eq 0 ] &&
        [ "$COLLISION_REVERT_RC" -eq 0 ] &&
        [ "$(count_backups "$COLLISION_HOME")" -eq 2 ] || return 1

    COLLISION_BACKUPS=$(backup_list "$COLLISION_HOME")
    COLLISION_FIRST=$(printf '%s\n' "$COLLISION_BACKUPS" | sed -n '1p')
    COLLISION_SECOND=$(printf '%s\n' "$COLLISION_BACKUPS" | sed -n '2p')
    [ -n "$COLLISION_FIRST" ] &&
        [ -n "$COLLISION_SECOND" ] &&
        [ "$COLLISION_FIRST" != "$COLLISION_SECOND" ] &&
        ! diff -q "$COLLISION_FIRST" "$COLLISION_SECOND" >/dev/null 2>&1
}

if ! ROOT=$(mktemp -d "${TMPDIR:-/tmp}/setup-yolo-codex-smoke.XXXXXX"); then
    printf 'FAIL 0 could not create temporary directory\n'
    exit 1
fi

FRESH_HOME="$ROOT/fresh"
FRESH_CONFIG="$FRESH_HOME/config.toml"
mkdir -p "$FRESH_HOME"
printf '%s\n' \
    'theme = "dark"' \
    'approval_policy = "never"' \
    'model = "gpt-5"' \
    'model_reasoning_effort = "high"' \
    'profile = "default"' \
    '[features]' \
    'enabled = true' \
    '' \
    '[projects."/x"]' \
    'sandbox_mode = "read-only"' > "$FRESH_CONFIG"
if CODEX_HOME="$FRESH_HOME" "$SCRIPT" > "$ROOT/fresh.out" 2>&1; then
    FRESH_RC=0
else
    FRESH_RC=$?
fi
check 1 'fresh config inserts top-level key before features and preserves table key' test "$FRESH_RC" -eq 0
check 2 'fresh config creates one backup' test "$(count_backups "$FRESH_HOME")" -eq 1
check 3 'fresh config has expected top-level and table values' check_fresh_config

FRESH_BEFORE_SECOND="$ROOT/fresh.before-second"
cp -- "$FRESH_CONFIG" "$FRESH_BEFORE_SECOND"
FRESH_BACKUPS_BEFORE=$(backup_list "$FRESH_HOME")
if CODEX_HOME="$FRESH_HOME" "$SCRIPT" > "$ROOT/fresh-second.out" 2>&1; then
    FRESH_SECOND_RC=0
else
    FRESH_SECOND_RC=$?
fi
FRESH_SECOND_OUTPUT="$ROOT/fresh-second.out"
FRESH_BACKUPS_AFTER=$(backup_list "$FRESH_HOME")
check 4 'second run succeeds without changing bytes or backup files' test "$FRESH_SECOND_RC" -eq 0
check 5 'second run reports nothing changed' check_second_run

EXISTING_HOME="$ROOT/existing"
EXISTING_CONFIG="$EXISTING_HOME/config.toml"
mkdir -p "$EXISTING_HOME"
printf '%s\n' \
    'model = "gpt-5"' \
    'sandbox_mode = "workspace-write"' \
    'approval_policy = "never"' \
    '[features]' \
    'enabled = true' \
    '[projects."/x"]' \
    'sandbox_mode = "read-only"' > "$EXISTING_CONFIG"
if CODEX_HOME="$EXISTING_HOME" "$SCRIPT" > "$ROOT/existing.out" 2>&1; then
    EXISTING_RC=0
else
    EXISTING_RC=$?
fi
check 6 'existing top-level key is replaced in place' test "$EXISTING_RC" -eq 0
check 7 'existing config preserves replacement position and table key' check_existing_config

DRY_HOME="$ROOT/dry-run"
DRY_CONFIG="$DRY_HOME/config.toml"
mkdir -p "$DRY_HOME"
printf '%s\n' \
    'model = "gpt-5"' \
    '[features]' \
    'enabled = true' > "$DRY_CONFIG"
DRY_BEFORE="$ROOT/dry-run.before"
cp -- "$DRY_CONFIG" "$DRY_BEFORE"
DRY_OUTPUT="$ROOT/dry-run.out"
if CODEX_HOME="$DRY_HOME" "$SCRIPT" --dry-run > "$DRY_OUTPUT" 2>&1; then
    DRY_RC=0
else
    DRY_RC=$?
fi
check 8 'dry-run succeeds without writing or backing up' test "$DRY_RC" -eq 0
check 9 'dry-run prints added sandbox_mode diff line' check_dry_run

FRESH_REVERT_OUTPUT="$ROOT/fresh-revert.out"
if CODEX_HOME="$FRESH_HOME" "$SCRIPT" --revert > "$FRESH_REVERT_OUTPUT" 2>&1; then
    REVERT_RC=0
else
    REVERT_RC=$?
fi
check 10 'revert succeeds with a backup' test "$REVERT_RC" -eq 0
check 11 'revert removes only top-level key and preserves table key' check_revert

MISSING_HOME="$ROOT/missing"
MISSING_CONFIG="$MISSING_HOME/config.toml"
if CODEX_HOME="$MISSING_HOME" "$SCRIPT" > "$ROOT/missing.out" 2>&1; then
    MISSING_RC=0
else
    MISSING_RC=$?
fi
check 12 'missing config is created with one key' test "$MISSING_RC" -eq 0
check 13 'missing config contains only sandbox_mode and no backup' check_missing_config

NO_HEADER_HOME="$ROOT/no-header"
NO_HEADER_CONFIG="$NO_HEADER_HOME/config.toml"
mkdir -p "$NO_HEADER_HOME"
printf '%s\n' \
    'model = "gpt-5"' \
    'approval_policy = "never"' \
    '# Keep this comment at end of file.' > "$NO_HEADER_CONFIG"
if CODEX_HOME="$NO_HEADER_HOME" "$SCRIPT" > "$ROOT/no-header.out" 2>&1; then
    NO_HEADER_RC=0
else
    NO_HEADER_RC=$?
fi
check 14 'config without headers appends sandbox_mode at end' test "$NO_HEADER_RC" -eq 0
check 15 'config without headers remains header-free with one key' check_no_header_config

MULTILINE_HOME="$ROOT/multiline-array"
MULTILINE_CONFIG="$MULTILINE_HOME/config.toml"
mkdir -p "$MULTILINE_HOME"
printf '%s\n' \
    'model = "x"' \
    'notify = [' \
    '  "python3",' \
    '  "n.py",' \
    ']' \
    '' \
    '[features]' \
    'a = 1' > "$MULTILINE_CONFIG"
if CODEX_HOME="$MULTILINE_HOME" "$SCRIPT" > "$ROOT/multiline-array.out" 2>&1; then
    MULTILINE_RC=0
else
    MULTILINE_RC=$?
fi
check 16 'multi-line top-level array stays intact' test "$MULTILINE_RC" -eq 0
check 17 'multi-line array gets sandbox_mode outside array' check_multiline_array_position
if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' >/dev/null 2>&1; then
    check 18 'multi-line array output parses as TOML' check_multiline_array_toml
else
    skip 18 'multi-line array output parses as TOML' 'python3/tomllib unavailable'
fi

COMMENT_HOME="$ROOT/comment-preheader"
COMMENT_CONFIG="$COMMENT_HOME/config.toml"
mkdir -p "$COMMENT_HOME"
printf '%s\n' \
    '# Keep this comment.' \
    '# Keep this one too.' \
    '[features]' \
    'a = 1' > "$COMMENT_CONFIG"
if CODEX_HOME="$COMMENT_HOME" "$SCRIPT" > "$ROOT/comment-preheader.out" 2>&1; then
    COMMENT_RC=0
else
    COMMENT_RC=$?
fi
check 19 'comment-only pre-header gets sandbox_mode before first header' test "$COMMENT_RC" -eq 0
check 20 'comment-only pre-header preserves comments' check_comment_preheader

COLLISION_HOME="$ROOT/backup-collision"
COLLISION_CONFIG="$COLLISION_HOME/config.toml"
mkdir -p "$COLLISION_HOME"
printf '%s\n' 'model = "gpt-5"' > "$COLLISION_CONFIG"
if CODEX_HOME="$COLLISION_HOME" "$SCRIPT" > "$ROOT/backup-collision-apply.out" 2>&1; then
    COLLISION_APPLY_RC=0
else
    COLLISION_APPLY_RC=$?
fi
if CODEX_HOME="$COLLISION_HOME" "$SCRIPT" --revert > "$ROOT/backup-collision-revert.out" 2>&1; then
    COLLISION_REVERT_RC=0
else
    COLLISION_REVERT_RC=$?
fi
check 21 'immediate apply and revert keep two distinct backups with different contents' check_backup_collision

exit "$FAILURES"
