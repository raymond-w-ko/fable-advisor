#!/usr/bin/env bash
set -eu

SCRIPT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/lane.sh
FAILURES=0
LANE=
LANE2=
LANE3=
LANE4=
BAD=
SECRET=
SECRET_MULTI=

cleanup() {
    local lane
    for lane in "$LANE" "$LANE2" "$LANE3" "$LANE4"; do
        if [ -n "$lane" ] && [ -d "$lane" ]; then
            "$SCRIPT" kill "$lane" >/dev/null 2>&1 || true
            "$SCRIPT" rm "$lane" >/dev/null 2>&1 || true
        fi
    done
    if [ -n "$BAD" ] && [ -d "$BAD" ]; then
        rmdir "$BAD" 2>/dev/null || true
    fi
    if [ -n "$SECRET" ]; then
        rm -f -- "$SECRET"
    fi
    if [ -n "$SECRET_MULTI" ]; then
        rm -f -- "$SECRET_MULTI"
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

check_no_leaf() {
    ! kill -0 "$LEAF_PID" 2>/dev/null
}

check_no_timeout() {
    [ -z "$(ps -o pid= -p "$TIMEOUT_PID" | tr -d '[:space:]')" ]
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

LANE=$("$SCRIPT" init smoke-lane)
check 1 'init creates mode 700 lane with shots directory' check_mode_700
check 2 'init creates shots directory' test -d "$LANE/shots"

printf 'input\n' >> "$LANE/stdin"
SECONDS=0
"$SCRIPT" launch "$LANE" -- sh -c 'cat >/dev/null; sleep 3; echo done >> "$1"; exit 3' _ "$LANE/final.txt" >/dev/null
LAUNCH_SECONDS=$SECONDS
check 3 'launch returns within 1 second' test "$LAUNCH_SECONDS" -lt 1
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
TIMEOUT_PID=$(pgrep -P "$PID2" | head -1)
LEAF_PID=$TIMEOUT_PID
while :; do
    CHILD_PID=$(pgrep -P "$LEAF_PID" 2>/dev/null | head -1 || true)
    [ -n "$CHILD_PID" ] || break
    LEAF_PID=$CHILD_PID
done
"$SCRIPT" kill "$LANE2"
check 11 'kill stops launch pid' check_no_pid2
check 12 'kill stops launched sleep leaf' check_no_leaf
check 12b 'kill stops timeout process' check_no_timeout
check 13 'kill records rc 137' grep -qx '137' "$LANE2/rc"

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
chmod 644 "$SECRET"
BEFORE_BYTES=$(wc -c < "$LANE4/stdin" | tr -d '[:space:]')
if "$SCRIPT" splice-secret "$LANE4" "$SECRET" >/dev/null 2>&1; then
    SPLICE_BAD_RC=0
else
    SPLICE_BAD_RC=$?
fi
AFTER_BYTES=$(wc -c < "$LANE4/stdin" | tr -d '[:space:]')
check 16 'splice-secret rejects mode 644 without appending' test "$SPLICE_BAD_RC" -eq 2
check 17 'rejected secret leaves stdin unchanged' test "$BEFORE_BYTES" -eq "$AFTER_BYTES"
chmod 600 "$SECRET"
SECRET_MULTI=$(mktemp "${TMPDIR:-/tmp}/lane-secret-multi.XXXXXX")
printf 'first-line\nsecond-line\n' >> "$SECRET_MULTI"
chmod 600 "$SECRET_MULTI"
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

exit "$FAILURES"
