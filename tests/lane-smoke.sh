#!/usr/bin/env bash
set -eu

SCRIPT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/lane.sh
FAILURES=0
LANE=
LANE2=
LANE3=
LANE4=
LANE5=
BAD=
SECRET=
SECRET_MULTI=
TEST_TMPDIR=
GC_TMPDIR=
GC_OLD=
GC_YOUNG=
GC_LIVE=
GC_NO_MARKER=
GC_INIT_OLD=
GC_INIT_LANE=
GC_INIT_STDERR=

case $(uname -s 2>/dev/null) in
    MINGW*|MSYS*|CYGWIN*) IS_MSYS=1 ;;
    *) IS_MSYS=0 ;;
esac

cleanup() {
    local lane
    for lane in "$LANE" "$LANE2" "$LANE3" "$LANE4" "$LANE5"; do
        if [ -n "$lane" ] && [ -d "$lane" ]; then
            "$SCRIPT" kill "$lane" >/dev/null 2>&1 || true
            "$SCRIPT" rm "$lane" >/dev/null 2>&1 || true
        fi
    done
    for lane in "$GC_OLD" "$GC_YOUNG" "$GC_LIVE" "$GC_INIT_OLD" "$GC_INIT_LANE"; do
        if [ -n "$lane" ] && [ -d "$lane" ]; then
            TMPDIR="$GC_TMPDIR" "$SCRIPT" kill "$lane" >/dev/null 2>&1 || true
            TMPDIR="$GC_TMPDIR" "$SCRIPT" rm "$lane" >/dev/null 2>&1 || true
        fi
    done
    if [ -n "$GC_NO_MARKER" ] && [ -d "$GC_NO_MARKER" ]; then
        rmdir "$GC_NO_MARKER" 2>/dev/null || true
    fi
    if [ -n "$GC_INIT_STDERR" ]; then
        rm -f -- "$GC_INIT_STDERR"
    fi
    if [ -n "$GC_TMPDIR" ] && [ -d "$GC_TMPDIR" ]; then
        rmdir "$GC_TMPDIR" 2>/dev/null || true
    fi
    if [ -n "$BAD" ] && [ -d "$BAD" ]; then
        rmdir "$BAD" 2>/dev/null || true
    fi
    if [ -n "$SECRET" ]; then
        rm -f -- "$SECRET"
    fi
    if [ -n "$SECRET_MULTI" ]; then
        rm -f -- "$SECRET_MULTI"
    fi
    if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
        rmdir "$TEST_TMPDIR" 2>/dev/null || true
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
    printf 'ok %s %s (skipped: %s)\n' "$1" "$2" "$3"
}

# First child pid of $1, without pgrep (absent on Git Bash).
first_child() {
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -P "$1" 2>/dev/null | head -1 || true
    else
        ps 2>/dev/null | awk -v p="$1" 'NR > 1 && $2 == p { print $1; exit }'
    fi
}

# Permission fixtures: POSIX modes elsewhere, ACLs on Windows.
make_secret_open() {
    if [ "$IS_MSYS" -eq 1 ]; then
        icacls "$(cygpath -w -- "$1")" //grant 'Everyone:R' >/dev/null
    else
        chmod 644 "$1"
    fi
}

make_secret_private() {
    if [ "$IS_MSYS" -eq 1 ]; then
        # reset first: /grant:r replaces the owner's entry only, explicit extras would survive
        icacls "$(cygpath -w -- "$1")" //reset >/dev/null
        icacls "$(cygpath -w -- "$1")" //inheritance:r //grant:r "$(whoami):F" >/dev/null
    else
        chmod 600 "$1"
    fi
}

check_mode_700() {
    local mode
    if mode=$(stat -c %a "$LANE" 2>/dev/null); then
        :
    else
        mode=$(stat -f %Lp "$LANE")
    fi
    [ "$mode" = 700 ]
}

check_launch_metadata() {
    [ -f "$LANE/pid" ] && [ -f "$LANE/started" ] && [ -f "$LANE/timeout-bin" ]
}

check_status_alive_yes() {
    case "$STATUS_BEFORE" in
        *'alive=yes'*) return 0 ;;
        *) return 1 ;;
    esac
}

check_status_alive_no() {
    case "$STATUS_AFTER" in
        *'alive=no'*) return 0 ;;
        *) return 1 ;;
    esac
}

check_wait_ready() {
    [ "$WAIT_OUTPUT" = 'READY rc=3' ]
}

check_wait_fast() {
    [ "$WAIT_SECONDS" -lt 10 ]
}

check_no_pid() {
    ! kill -0 "$PID" 2>/dev/null
}

check_no_pid2() {
    ! kill -0 "$PID2" 2>/dev/null
}

check_leaf_found() {
    [ -n "$LEAF_PID" ] && [ "$LEAF_PID" != "$PID2" ]
}

check_no_leaf() {
    ! kill -0 "$LEAF_PID" 2>/dev/null
}

check_no_timeout() {
    ! kill -0 "$TIMEOUT_PID" 2>/dev/null
}

count_node_markers() {
    if [ "$IS_MSYS" -eq 1 ]; then
        powershell -NoProfile -Command \
            "(Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { \$_.CommandLine -like '*lane-smoke-marker*' }).Count"
    else
        # timeout's and launch's command lines carry the marker too; match only
        # lines whose argv[0] is node. No pgrep -c: BSD pgrep lacks it.
        pgrep -f '(^|/)node -e .*lane-smoke-marker' 2>/dev/null | wc -l
    fi | tr -d '[:space:]'
}

check_no_grandchild() {
    [ "$(count_node_markers)" = 0 ]
}

check_deadline_expired() {
    [ "$DEADLINE_RC" -eq 1 ] && [ "$DEADLINE_OUTPUT" = EXPIRED ]
}

check_deadline_ok() {
    case "$DEADLINE_DEFAULT" in
        OK\ remaining=*) return 0 ;;
        *) return 1 ;;
    esac
}

backdate_file() {
    local file=$1 gnu_offset=$2 bsd_offset=$3
    if touch -d "$gnu_offset" "$file" 2>/dev/null; then
        return 0
    fi
    touch -t "$(date -v"$bsd_offset" '+%Y%m%d%H%M.%S')" "$file"
}

check_one_line() {
    [ -n "$GC_INIT_OUTPUT" ] || return 1
    [ "$(printf '%s\n' "$GC_INIT_OUTPUT" | wc -l | tr -d '[:space:]')" -eq 1 ]
}

check_scrub_counts() {
    case "$SCRUB_OUTPUT" in
        *'secret-matches=1'*) return 0 ;;
        *) return 1 ;;
    esac
}

check_bad_rm() {
    [ "$BAD_RC" -eq 2 ] && [ -d "$BAD" ]
}

check_real_rm() {
    [ ! -d "$LANE3" ]
}

check_host_path() {
    case "$LANE" in
        /tmp/*) [ "$IS_MSYS" -eq 0 ] ;;
        [A-Za-z]:/*) [ "$IS_MSYS" -eq 1 ] ;;
        *) return 0 ;;
    esac
}

TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/lane-smoke.XXXXXX")
export TMPDIR="$TEST_TMPDIR"

LANE=$("$SCRIPT" init smoke-lane)
if [ "$IS_MSYS" -eq 1 ]; then
    skip 1 'init creates mode 700 lane' 'no POSIX modes on Windows; %TEMP% ACL scopes it'
else
    check 1 'init creates mode 700 lane with shots directory' check_mode_700
fi
check 1b 'init prints a path the host tools accept' check_host_path
check 2 'init creates shots directory' test -d "$LANE/shots"

printf 'input\n' >> "$LANE/stdin"
SECONDS=0
"$SCRIPT" launch "$LANE" -- sh -c 'cat >/dev/null; sleep 3; echo done >> "$1"; exit 3' _ "$LANE/final.txt" >/dev/null
LAUNCH_SECONDS=$SECONDS
# Process spawn on Windows is slower; the point is that launch does not wait for the command.
check 3 'launch returns without waiting for the command' test "$LAUNCH_SECONDS" -lt 3
check 4 'launch writes metadata files' check_launch_metadata
PID=$(cat "$LANE/pid")
STATUS_BEFORE=$("$SCRIPT" status "$LANE")
check 5 'status reports live launch' check_status_alive_yes

SECONDS=0
WAIT_OUTPUT=$("$SCRIPT" wait "$LANE")
WAIT_SECONDS=$SECONDS
check 6 'wait reports ready rc 3' check_wait_ready
check 7 'wait returns within 10 seconds' check_wait_fast
check 8 'dummy command writes final file' grep -q '^done$' "$LANE/final.txt"
STATUS_AFTER=$("$SCRIPT" status "$LANE")
check 9 'status reports stopped launch' check_status_alive_no
check 10 'launch pid no longer exists' check_no_pid

LANE2=$("$SCRIPT" init smoke-lane)
printf '\n' >> "$LANE2/stdin"
"$SCRIPT" launch "$LANE2" -- sh -c 'sleep 60' >/dev/null
PID2=$(cat "$LANE2/pid")
sleep 1
TIMEOUT_PID=$(first_child "$PID2")
LEAF_PID=$TIMEOUT_PID
while :; do
    CHILD_PID=$(first_child "$LEAF_PID")
    [ -n "$CHILD_PID" ] || break
    LEAF_PID=$CHILD_PID
done
check 11a 'test harness can see the launched process tree' check_leaf_found
"$SCRIPT" kill "$LANE2"
check 11 'kill stops launch pid' check_no_pid2
check 12 'kill stops launched sleep leaf' check_no_leaf
check 12b 'kill stops timeout process' check_no_timeout
check 13 'kill records rc 137' grep -qx '137' "$LANE2/rc"

# A native child that spawns its own child, like codex starting an MCP server.
if command -v node >/dev/null 2>&1; then
    LANE5=$("$SCRIPT" init smoke-lane)
    printf '\n' >> "$LANE5/stdin"
    "$SCRIPT" launch "$LANE5" -- node -e "require('child_process').spawn(process.execPath, ['-e', 'setInterval(()=>{},1000) // lane-smoke-marker'], {stdio: 'ignore'}); setInterval(()=>{},1000) // lane-smoke-marker" >/dev/null
    sleep 2
    check 12c-pre 'native child and grandchild are running before kill' test "$(count_node_markers)" = 2
    "$SCRIPT" kill "$LANE5"
    sleep 1
    check 12c 'kill stops a native grandchild' check_no_grandchild
else
    skip 12c 'kill stops a native grandchild' 'node not on PATH'
fi

LANE3=$("$SCRIPT" init smoke-lane)
printf '%s\n' "$(( $(date +%s) - 5 ))" >> "$LANE3/started"
if DEADLINE_OUTPUT=$("$SCRIPT" deadline "$LANE3" 1); then
    DEADLINE_RC=0
else
    DEADLINE_RC=$?
fi
check 14 'deadline reports expired lane' check_deadline_expired
DEADLINE_DEFAULT=$("$SCRIPT" deadline "$LANE3")
check 15 'deadline reports default window as ok' check_deadline_ok

LANE4=$("$SCRIPT" init smoke-lane)
printf '\n' >> "$LANE4/stdin"
SECRET=$(mktemp "${TMPDIR:-/tmp}/lane-secret.XXXXXX")
printf 'hunter2-example\n' >> "$SECRET"
make_secret_open "$SECRET"
BEFORE_BYTES=$(wc -c < "$LANE4/stdin" | tr -d '[:space:]')
if "$SCRIPT" splice-secret "$LANE4" "$SECRET" >/dev/null 2>&1; then
    SPLICE_BAD_RC=0
else
    SPLICE_BAD_RC=$?
fi
AFTER_BYTES=$(wc -c < "$LANE4/stdin" | tr -d '[:space:]')
check 16 'splice-secret rejects a readable-by-others secret without appending' test "$SPLICE_BAD_RC" -eq 2
check 17 'rejected secret leaves stdin unchanged' test "$BEFORE_BYTES" -eq "$AFTER_BYTES"
make_secret_private "$SECRET"
SECRET_MULTI=$(mktemp "${TMPDIR:-/tmp}/lane-secret-multi.XXXXXX")
printf 'first-line\nsecond-line\n' >> "$SECRET_MULTI"
make_secret_private "$SECRET_MULTI"
if "$SCRIPT" splice-secret "$LANE4" "$SECRET_MULTI" >/dev/null 2>&1; then
    SPLICE_MULTI_BAD_RC=0
else
    SPLICE_MULTI_BAD_RC=$?
fi
check 18 'splice-secret rejects two-line secret' test "$SPLICE_MULTI_BAD_RC" -eq 2
"$SCRIPT" splice-secret "$LANE4" "$SECRET"
check 19 'splice-secret appends secret once' test "$(grep -c hunter2-example "$LANE4/stdin")" -eq 1
printf 'result hunter2-example\n' >> "$LANE4/final.txt"
printf 'output hunter2-example\n' >> "$LANE4/stdout.log"
printf '{}\n' >> "$LANE4/events.jsonl"
SCRUB_OUTPUT=$("$SCRIPT" scrub "$LANE4")
check 20 'scrub reports secret match counts' check_scrub_counts
check 21 'scrub removes stdin' test ! -e "$LANE4/stdin"
check 22 'scrub removes stdout' test ! -e "$LANE4/stdout.log"
check 23 'scrub withholds matching final' test ! -e "$LANE4/final.txt" && grep -q 'withheld' <<<"$SCRUB_OUTPUT"
printf 'safe result\n' >> "$LANE4/final.txt"
"$SCRIPT" scrub "$LANE4" >/dev/null
check 24 'scrub keeps non-matching final' test -f "$LANE4/final.txt"

BAD=$(mktemp -d "${TMPDIR:-/tmp}/fake-lane.XXXXXX")
if "$SCRIPT" rm "$BAD" >/dev/null 2>&1; then
    BAD_RC=0
else
    BAD_RC=$?
fi
check 25 'rm refuses matching name without marker' check_bad_rm
"$SCRIPT" rm "$LANE3"
check 26 'rm removes real lane' check_real_rm

GC_TMPDIR=$(mktemp -d "$TEST_TMPDIR/gc.XXXXXX")
GC_OLD=$(TMPDIR="$GC_TMPDIR" "$SCRIPT" init old-lane 2>/dev/null)
printf '0\n' >> "$GC_OLD/rc"
backdate_file "$GC_OLD/rc" '-2 hours' '-2H'
GC_YOUNG=$(TMPDIR="$GC_TMPDIR" "$SCRIPT" init young-lane 2>/dev/null)
printf '0\n' >> "$GC_YOUNG/rc"
GC_LIVE=$(TMPDIR="$GC_TMPDIR" "$SCRIPT" init live-lane 2>/dev/null)
GC_NO_MARKER="$GC_TMPDIR/no-marker-lane.fixture"
mkdir -p "$GC_NO_MARKER"
GC_OUTPUT=$(TMPDIR="$GC_TMPDIR" "$SCRIPT" gc 1)
check 27 'gc reports removed old finished lane' grep -q "gc removed $GC_OLD" <<<"$GC_OUTPUT"
check 28 'gc removes old finished lane' test ! -d "$GC_OLD"
check 29 'gc keeps young finished lane' test -d "$GC_YOUNG"
check 30 'gc keeps live lane without rc' test -d "$GC_LIVE"
check 31 'gc keeps lane without marker' test -d "$GC_NO_MARKER"

GC_INIT_OLD=$(TMPDIR="$GC_TMPDIR" "$SCRIPT" init init-old-lane 2>/dev/null)
printf '0\n' >> "$GC_INIT_OLD/rc"
backdate_file "$GC_INIT_OLD/rc" '-2 days' '-2d'
GC_INIT_STDERR=$(mktemp "$TEST_TMPDIR/gc-init.stderr.XXXXXX")
GC_INIT_OUTPUT=$(TMPDIR="$GC_TMPDIR" "$SCRIPT" init init-new-lane 2>"$GC_INIT_STDERR")
GC_INIT_LANE=$GC_INIT_OUTPUT
check 32 'init prints one lane path line' check_one_line
check 33 'init runs gc for old finished lane' test ! -d "$GC_INIT_OLD"
check 34 'init sends gc output to stderr' grep -q "gc removed $GC_INIT_OLD" "$GC_INIT_STDERR"

USAGE_OUTPUT=$("$SCRIPT" --help 2>&1 || true)
check 35 'usage lists gc' grep -q '  gc \[hours\]' <<<"$USAGE_OUTPUT"
check 36 'lane cap is 5340 seconds' grep -qx 'CAP=5340' "$SCRIPT"
check 37 'lane deadline is 5400 seconds' grep -qx 'DEADLINE=5400' "$SCRIPT"

REUSED_LANE=$(TMPDIR="$GC_TMPDIR" "$SCRIPT" init reused-lane 2>/dev/null)
printf 'noop\n' >> "$REUSED_LANE/stdin"
printf '0\n' >> "$REUSED_LANE/rc"
launch_refuses_reuse() {
    ! "$SCRIPT" launch "$REUSED_LANE" -- true >/dev/null 2>&1
}
check 38 'launch refuses a lane that already ran' launch_refuses_reuse

exit "$FAILURES"
