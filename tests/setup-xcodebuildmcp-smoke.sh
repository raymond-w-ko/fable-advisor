#!/usr/bin/env bash
set -eu

SCRIPT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/setup-xcodebuildmcp.sh
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

default_block() {
    awk '
        /^\[mcp_servers\.xcodebuildmcp\]$/ { p = 1 }
        p && /^\[/ && $0 != "[mcp_servers.xcodebuildmcp]" { exit }
        p { print }' "$CONFIG"
}

check_launcher_block() {
    [ "$(count_exact '[mcp_servers.xcodebuildmcp]' "$CONFIG")" -eq 1 ] &&
        grep -Fqx "command = \"$FAKE_LAUNCHER\"" "$CONFIG" &&
        grep -Fqx 'args = ["mcp"]' "$CONFIG"
}

if ! ROOT=$(mktemp -d "${TMPDIR:-/tmp}/setup-xcodebuildmcp-smoke.XXXXXX"); then
    printf 'FAIL 0 could not create temporary directory\n'
    exit 1
fi

SKIP_REASON=
if [ "$(uname -s 2>/dev/null || true)" != Darwin ]; then
    SKIP_REASON='macOS required'
elif ! xcode-select -p >/dev/null 2>&1; then
    SKIP_REASON='Xcode command line tools unavailable'
fi
if [ -n "$SKIP_REASON" ]; then
    skip 1 '--check reports missing block' "$SKIP_REASON"
    skip 2 'real run writes launcher block and one backup' "$SKIP_REASON"
    skip 3 '--check accepts written block' "$SKIP_REASON"
    skip 4 'second run returns block-present status without backup' "$SKIP_REASON"
    skip 5 '--force replaces block with one new backup' "$SKIP_REASON"
    skip 6 '--name writes second block without changing first' "$SKIP_REASON"
    skip 7 '--bogus returns usage status' "$SKIP_REASON"
    exit 0
fi

BIN="$ROOT/bin"
CODEX_HOME="$ROOT/codex"
CONFIG="$CODEX_HOME/config.toml"
mkdir -p "$BIN" "$CODEX_HOME"
: > "$CONFIG"

printf '%s\n' \
    '#!/bin/sh' \
    '[ "$1" = mcp ] && [ "$2" = get ] && exit 0' \
    'exit 1' > "$BIN/codex"
chmod +x "$BIN/codex"

FAKE_LAUNCHER="$BIN/fake-xcodebuildmcp"
printf '%s\n' \
    '#!/usr/bin/env python3' \
    'import json' \
    'import sys' \
    '' \
    'for line in sys.stdin:' \
    '    try:' \
    '        request = json.loads(line)' \
    '    except json.JSONDecodeError:' \
    '        continue' \
    '    method = request.get("method")' \
    '    if method == "initialize":' \
    '        print(json.dumps({"jsonrpc": "2.0", "id": request.get("id"), "result": {"protocolVersion": "2025-03-26", "capabilities": {}, "serverInfo": {"name": "fake-xcodebuildmcp", "version": "0"}}}), flush=True)' \
    '    elif method == "tools/list":' \
    '        names = ["list_sims", "snapshot_ui", "screenshot", "launch_app_sim"]' \
    '        print(json.dumps({"jsonrpc": "2.0", "id": request.get("id"), "result": {"tools": [{"name": name} for name in names]}}), flush=True)' > "$FAKE_LAUNCHER"
chmod +x "$FAKE_LAUNCHER"

PERL_PATH=$(command -v perl 2>/dev/null || true)
PERL_BIN_DIR=
if [ -n "$PERL_PATH" ]; then
    PERL_BIN_DIR=$(dirname "$PERL_PATH")
fi

# Keep GNU timeout out of baseline PATH so cases 1-16 exercise perl alarm.
PATH_WITHOUT_GNU_TIMEOUT=
PATH_IFS=$IFS
IFS=:
for PATH_ENTRY in $PATH; do
    [ -n "$PATH_ENTRY" ] || PATH_ENTRY=.
    if [ -x "$PATH_ENTRY/gtimeout" ]; then
        continue
    fi
    if [ -x "$PATH_ENTRY/timeout" ] && "$PATH_ENTRY/timeout" --version 2>/dev/null | grep -qi coreutils; then
        continue
    fi
    if [ -n "$PATH_WITHOUT_GNU_TIMEOUT" ]; then
        PATH_WITHOUT_GNU_TIMEOUT=$PATH_WITHOUT_GNU_TIMEOUT:$PATH_ENTRY
    else
        PATH_WITHOUT_GNU_TIMEOUT=$PATH_ENTRY
    fi
done
IFS=$PATH_IFS

TEST_PATH="$BIN:$PERL_BIN_DIR:$PATH_WITHOUT_GNU_TIMEOUT"

if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH" "$SCRIPT" --check --launcher "$FAKE_LAUNCHER" > "$ROOT/check-empty.out" 2>&1; then
    CHECK_EMPTY_RC=0
else
    CHECK_EMPTY_RC=$?
fi
check 1 '--check on empty config returns missing status and reports block' test "$CHECK_EMPTY_RC" -eq 1
check 2 '--check on empty config prints MISSING for block' grep -q '^MISSING: \[mcp_servers.xcodebuildmcp\]' "$ROOT/check-empty.out"

if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH" "$SCRIPT" --launcher "$FAKE_LAUNCHER" > "$ROOT/first.out" 2>&1; then
    FIRST_RC=0
else
    FIRST_RC=$?
fi
check 3 'real run writes launcher block and returns success' test "$FIRST_RC" -eq 0
check 4 'real run writes launcher command and mcp args with one backup' check_launcher_block
check 5 'real run creates one backup' test "$(count_backups "$CODEX_HOME")" -eq 1

if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH" "$SCRIPT" --check --launcher "$FAKE_LAUNCHER" > "$ROOT/check-written.out" 2>&1; then
    CHECK_WRITTEN_RC=0
else
    CHECK_WRITTEN_RC=$?
fi
check 6 '--check accepts written block' test "$CHECK_WRITTEN_RC" -eq 0

BACKUPS_BEFORE=$(count_backups "$CODEX_HOME")
if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH" "$SCRIPT" --launcher "$FAKE_LAUNCHER" > "$ROOT/second.out" 2>&1; then
    SECOND_RC=0
else
    SECOND_RC=$?
fi
check 7 'second run returns block-present status' test "$SECOND_RC" -eq 3
check 8 'second run creates no backup' test "$(count_backups "$CODEX_HOME")" -eq "$BACKUPS_BEFORE"

if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH" "$SCRIPT" --force --launcher "$FAKE_LAUNCHER" > "$ROOT/force.out" 2>&1; then
    FORCE_RC=0
else
    FORCE_RC=$?
fi
check 9 '--force replaces block' test "$FORCE_RC" -eq 0
check 10 '--force leaves one block and creates one more backup' test "$(count_exact '[mcp_servers.xcodebuildmcp]' "$CONFIG")" -eq 1
check 11 '--force creates one more backup' test "$(count_backups "$CODEX_HOME")" -eq 2

DEFAULT_BEFORE_OTHER=$(default_block)
if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH" "$SCRIPT" --name other --launcher "$FAKE_LAUNCHER" > "$ROOT/other.out" 2>&1; then
    OTHER_RC=0
else
    OTHER_RC=$?
fi
check 12 '--name writes second block' test "$OTHER_RC" -eq 0
check 13 '--name leaves first block undisturbed' test "$(default_block)" = "$DEFAULT_BEFORE_OTHER"
check 14 '--name produces exactly two MCP blocks' test "$(count_exact '[mcp_servers.xcodebuildmcp]' "$CONFIG")" -eq 1
check 15 '--name produces exactly one alternate block' test "$(count_exact '[mcp_servers.other]' "$CONFIG")" -eq 1

if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH" "$SCRIPT" --bogus > "$ROOT/bogus.out" 2>&1; then
    BOGUS_RC=0
else
    BOGUS_RC=$?
fi
check 16 '--bogus returns usage status' test "$BOGUS_RC" -eq 2

GNU_BIN="$ROOT/gnu-bin"
mkdir -p "$GNU_BIN"
printf '%s\n' \
    '#!/bin/sh' \
    'if [ "$1" = --version ]; then printf "%s\\n" "timeout (GNU coreutils) 9.0"; exit 0; fi' \
    '[ "$1" = -k ] && [ "$2" = 5 ] && [ "$3" = 90 ] || exit 2' \
    'shift 3' \
    'exec "$@"' > "$GNU_BIN/gtimeout"
chmod +x "$GNU_BIN/gtimeout"

TEST_PATH_GNU="$GNU_BIN:$TEST_PATH"
if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH_GNU" "$SCRIPT" --force --launcher "$FAKE_LAUNCHER" > "$ROOT/gnu-timeout.out" 2>&1; then
    GNU_TIMEOUT_RC=0
else
    GNU_TIMEOUT_RC=$?
fi
gnu_timeout_case() {
    [ "$GNU_TIMEOUT_RC" -eq 0 ] && grep -q 'handshake bound: GNU timeout' "$ROOT/gnu-timeout.out"
}
check 17 'gtimeout bound runs real handshake' gnu_timeout_case

SLEEP_LAUNCHER="$BIN/sleep-xcodebuildmcp"
printf '%s\n' \
    '#!/bin/sh' \
    'sleep 300' > "$SLEEP_LAUNCHER"
chmod +x "$SLEEP_LAUNCHER"

if CODEX_HOME="$CODEX_HOME" PATH="$TEST_PATH" perl -e 'alarm 100; exec @ARGV' "$SCRIPT" --check --launcher "$SLEEP_LAUNCHER" > "$ROOT/sleep.out" 2>&1; then
    SLEEP_RC=0
else
    SLEEP_RC=$?
fi
sleep_case() {
    [ "$SLEEP_RC" -ne 142 ] && grep -q 'MISSING: handshake' "$ROOT/sleep.out"
}
check 18 'sleeping launcher returns before external 100-second bound with missing handshake' sleep_case

exit "$FAILURES"
