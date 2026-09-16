#!/usr/bin/env bash
set -eu

CAP=3540
DEADLINE=3600
KILL_GRACE=15
# CAP is generous on purpose because an interrupted codex run loses its verification and final message.

usage() {
    printf '%s\n' \
        'Usage: scripts/lane.sh <subcommand> [args]' \
        '' \
        'Subcommands:' \
        '  init <prefix>' \
        '  launch <lane-dir> -- <command and args...>' \
        '  wait <lane-dir> [seconds]' \
        '  status <lane-dir>' \
        '  kill <lane-dir>' \
        '  deadline <lane-dir> [seconds]' \
        '  splice-secret <lane-dir> <secret-file>' \
        '  scrub <lane-dir>' \
        '  rm <lane-dir>' >&2
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

require_lane() {
    [ -d "$1" ] || fail "lane directory missing: $1"
}

require_seconds() {
    case "$1" in
        ''|*[!0-9]*) fail "seconds must be a non-negative integer: $1" ;;
    esac
}

find_gnu_timeout() {
    local candidate
    for candidate in gtimeout timeout; do
        if command -v "$candidate" >/dev/null 2>&1 && \
            "$candidate" --version 2>/dev/null | grep -qi coreutils; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    printf '\n'
}

find_gnu_tail() {
    local candidate
    for candidate in gtail tail; do
        if command -v "$candidate" >/dev/null 2>&1 && \
            "$candidate" --version 2>/dev/null | grep -qi coreutils; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    printf '\n'
}

line_count() {
    if [ -f "$1" ]; then
        wc -l < "$1" | tr -d '[:space:]'
    else
        printf '0\n'
    fi
}

collect_descendants() {
    local parent=$1
    local children child

    # Walk parent-child PIDs; command-line matching can kill this shell.
    children=$(pgrep -P "$parent" 2>/dev/null || true)
    while IFS= read -r child; do
        [ -n "$child" ] || continue
        DESCENDANTS+=("$child")
        collect_descendants "$child"
    done <<EOF
$children
EOF
}

secure_delete() {
    local file=$1
    local size

    if command -v shred >/dev/null 2>&1; then
        if shred -u -- "$file" 2>/dev/null; then
            return 0
        fi
    fi
    size=$(wc -c < "$file" | tr -d '[:space:]')
    if [ "$size" -gt 0 ]; then
        dd if=/dev/zero of="$file" bs="$size" count=1 conv=notrunc \
            >/dev/null 2>&1
    fi
    rm -f -- "$file"
}

cmd_init() {
    [ "$#" -eq 1 ] || fail 'init requires prefix'
    umask 077
    local lane
    lane=$(mktemp -d "${TMPDIR:-/tmp}/$1.XXXXXX") || fail 'mktemp failed'
    mkdir -p "$lane/shots"
    : >> "$lane/.lane-marker"
    printf '%s\n' "$lane"
}

cmd_launch() {
    [ "$#" -ge 3 ] || fail 'launch requires lane directory, --, and command'
    local lane=$1
    shift
    [ "$1" = '--' ] || fail 'launch requires -- before command'
    shift
    [ "$#" -gt 0 ] || fail 'launch requires command'
    require_lane "$lane"
    [ -f "$lane/stdin" ] || fail "missing stdin: $lane/stdin"

    local timeout_bin
    timeout_bin=$(find_gnu_timeout)
    if [ -z "$timeout_bin" ]; then
        printf '%s\n' 'WARN: no GNU timeout on PATH — run is uncapped (macOS: brew install coreutils)' >&2
    else
        set -- "$timeout_bin" -k "$KILL_GRACE" "$CAP" "$@"
    fi

    # set -m gives detached background subshell its own process group.
    set -m 2>/dev/null || true
    (
        local rc
        set +e
        "$@" < "$lane/stdin" >> "$lane/stdout.log" 2>> "$lane/stderr.log"
        rc=$?
        printf '%s\n' "$rc" >> "$lane/rc"
        exit "$rc"
    ) >/dev/null 2>&1 &
    local pid
    pid=$!
    set +m 2>/dev/null || true
    # Fresh lane files use append redirects because command guards reject variable-path >.
    printf '%s\n' "$pid" >> "$lane/pid"
    printf '%s\n' "$timeout_bin" >> "$lane/timeout-bin"
    date +%s >> "$lane/started"
    printf '%s\n' "$lane"
}

cmd_wait() {
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail 'wait requires lane directory and optional seconds'
    local lane=$1
    local seconds=${2:-550}
    require_lane "$lane"
    require_seconds "$seconds"
    local timeout_bin tail_bin pid iterations i started elapsed remaining
    timeout_bin=$(cat "$lane/timeout-bin")
    pid=$(cat "$lane/pid")
    started=$(cat "$lane/started")
    elapsed=$(( $(date +%s) - started ))
    remaining=$((DEADLINE - elapsed))
    [ "$remaining" -ge 1 ] || remaining=1
    if [ "$seconds" -gt "$remaining" ]; then
        seconds=$remaining
    fi
    tail_bin=$(find_gnu_tail)

    if [ -n "$timeout_bin" ] && [ -n "$tail_bin" ]; then
        "$timeout_bin" "$seconds" "$tail_bin" "--pid=$pid" -f /dev/null \
            >/dev/null 2>&1 || true
    else
        iterations=$((seconds / 10))
        i=0
        while [ "$i" -lt "$iterations" ]; do
            [ -f "$lane/rc" ] && break
            sleep 10
            i=$((i + 1))
        done
    fi

    if [ -f "$lane/rc" ]; then
        printf 'READY rc=%s\n' "$(cat "$lane/rc")"
    else
        printf 'NOT_READY elapsed=%ss\n' "$(( $(date +%s) - $(cat "$lane/started") ))"
    fi
}

cmd_status() {
    [ "$#" -eq 1 ] || fail 'status requires lane directory'
    local lane=$1
    require_lane "$lane"
    local pid started now alive rc stdout_lines stderr_lines elapsed
    pid=$(cat "$lane/pid")
    started=$(cat "$lane/started")
    now=$(date +%s)
    elapsed=$((now - started))
    if kill -0 "$pid" 2>/dev/null; then
        alive=yes
    else
        alive=no
    fi
    if [ -f "$lane/rc" ]; then
        rc=$(cat "$lane/rc")
    else
        rc=none
    fi
    stdout_lines=$(line_count "$lane/stdout.log")
    stderr_lines=$(line_count "$lane/stderr.log")
    printf 'pid=%s alive=%s elapsed=%ss rc=%s stdout_lines=%s stderr_lines=%s\n' \
        "$pid" "$alive" "$elapsed" "$rc" "$stdout_lines" "$stderr_lines"
}

cmd_kill() {
    [ "$#" -eq 1 ] || fail 'kill requires lane directory'
    local lane=$1
    require_lane "$lane"
    local pid i child alive
    pid=$(cat "$lane/pid")
    # GNU timeout calls setpgid, so its process group differs from wrapper's group.
    DESCENDANTS=()
    collect_descendants "$pid"
    kill -TERM -- "-$pid" 2>/dev/null || true
    for child in ${DESCENDANTS[@]+"${DESCENDANTS[@]}"}; do
        kill -TERM "$child" 2>/dev/null || true
        kill -TERM -- "-$child" 2>/dev/null || true
    done
    i=0
    while [ "$i" -lt "$KILL_GRACE" ]; do
        alive=0
        kill -0 "$pid" 2>/dev/null && alive=1
        for child in ${DESCENDANTS[@]+"${DESCENDANTS[@]}"}; do
            kill -0 "$child" 2>/dev/null && alive=1
        done
        if [ "$alive" -eq 0 ]; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done
    DESCENDANTS=()
    collect_descendants "$pid"
    kill -KILL -- "-$pid" 2>/dev/null || true
    for child in ${DESCENDANTS[@]+"${DESCENDANTS[@]}"}; do
        kill -KILL "$child" 2>/dev/null || true
        kill -KILL -- "-$child" 2>/dev/null || true
    done
    if [ ! -f "$lane/rc" ]; then
        printf '137\n' >> "$lane/rc"
    fi
}

cmd_deadline() {
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail 'deadline requires lane directory and optional seconds'
    local lane=$1
    local seconds=${2:-$DEADLINE}
    require_lane "$lane"
    require_seconds "$seconds"
    local elapsed remaining
    elapsed=$(( $(date +%s) - $(cat "$lane/started") ))
    if [ ! -f "$lane/rc" ] && [ "$elapsed" -ge "$seconds" ]; then
        printf 'EXPIRED\n'
        return 1
    fi
    remaining=$((seconds - elapsed))
    [ "$remaining" -ge 0 ] || remaining=0
    printf 'OK remaining=%ss\n' "$remaining"
}

cmd_splice_secret() {
    [ "$#" -eq 2 ] || fail 'splice-secret requires lane directory and secret file'
    local lane=$1
    local secret=$2
    local mode secret_lines content_lines blank_lines
    require_lane "$lane"
    [ -f "$secret" ] || fail "secret file missing: $secret"
    [ -s "$secret" ] || fail 'secret file empty'
    if mode=$(stat -c %a "$secret" 2>/dev/null); then
        :
    elif mode=$(stat -f %Lp "$secret" 2>/dev/null); then
        :
    else
        fail 'cannot inspect secret file permissions'
    fi
    case "$mode" in
        600|400) ;;
        *) fail 'secret file must have mode 600 or 400' ;;
    esac
    secret_lines=$(wc -l < "$secret" | tr -d '[:space:]')
    content_lines=$(grep -c '^' "$secret" 2>/dev/null || true)
    blank_lines=$(grep -c '^$' "$secret" 2>/dev/null || true)
    if [ "$secret_lines" -gt 1 ] || [ "$content_lines" -gt 1 ] || [ "$blank_lines" -ne 0 ]; then
        fail 'secret file must hold exactly one non-empty line'
    fi
    printf '\nCredential for the authorized login flow above (type it only into that field): ' >> "$lane/stdin"
    cat "$secret" >> "$lane/stdin"
    printf '\n' >> "$lane/stdin"
    printf '%s\n' "$secret" >> "$lane/secret-path"
}

cmd_scrub() {
    [ "$#" -eq 1 ] || fail 'scrub requires lane directory'
    local lane=$1
    require_lane "$lane"
    [ -f "$lane/secret-path" ] || {
        printf 'no secret spliced\n'
        return 0
    }
    local secret file count scrubbed stdout_lines kept dropped
    secret=$(cat "$lane/secret-path")
    [ -f "$secret" ] || fail 'secret file missing during scrub'
    if [ -f "$lane/events.redacted.log" ]; then
        secure_delete "$lane/events.redacted.log"
    fi
    : >> "$lane/events.redacted.log"
    if [ -f "$lane/stdout.log" ]; then
        # grep -F on raw value misses JSON-escaped forms; caller should avoid `"` and `\` in secrets.
        grep -v -F -f "$secret" "$lane/stdout.log" >> "$lane/events.redacted.log" 2>/dev/null || true
        stdout_lines=$(line_count "$lane/stdout.log")
    else
        stdout_lines=0
    fi
    kept=$(line_count "$lane/events.redacted.log")
    dropped=$((stdout_lines - kept))
    printf 'events.redacted.log: kept=%s dropped=%s\n' "$kept" "$dropped"
    scrubbed=
    file="$lane/final.txt"
    if [ -f "$file" ]; then
        count=$(grep -c -F -f "$secret" "$file" 2>/dev/null || true)
    else
        count=0
    fi
    printf '%s: secret-matches=%s\n' "$file" "$count"
    if [ "$count" -ne 0 ]; then
        secure_delete "$file"
        scrubbed="$scrubbed $file"
        printf 'final.txt: withheld (contained the credential)\n'
    fi

    file="$lane/stderr.log"
    if [ -f "$file" ]; then
        count=$(grep -c -F -f "$secret" "$file" 2>/dev/null || true)
        printf '%s: secret-matches=%s\n' "$file" "$count"
        if [ "$count" -ne 0 ]; then
            secure_delete "$file"
            scrubbed="$scrubbed $file"
            printf 'stderr.log: withheld (contained the credential)\n'
        fi
    else
        printf '%s: secret-matches=0\n' "$file"
    fi
    if [ -f "$lane/stdout.log" ]; then
        secure_delete "$lane/stdout.log"
    fi
    scrubbed="$scrubbed $lane/stdout.log"
    for file in "$lane/stdin" "$lane/events.jsonl"; do
        if [ -f "$file" ]; then
            secure_delete "$file"
            scrubbed="$scrubbed $file"
        fi
    done
    printf 'scrubbed:%s\n' "$scrubbed"
}

cmd_rm() {
    [ "$#" -eq 1 ] || fail 'rm requires lane directory'
    local lane=$1 base lane_parent tmp_parent
    [ -d "$lane" ] || fail 'refusing: not a lane scratch dir'
    [ -f "$lane/.lane-marker" ] || fail 'refusing: not a lane scratch dir'
    lane_parent=$(CDPATH='' cd -- "$lane/.." && pwd -P) || fail 'refusing: not a lane scratch dir'
    tmp_parent=$(CDPATH='' cd -- "${TMPDIR:-/tmp}" && pwd -P) || fail 'refusing: not a lane scratch dir'
    [ "$lane_parent" = "$tmp_parent" ] || fail 'refusing: not a lane scratch dir'
    base=${lane##*/}
    case "$base" in
        *-lane.*) ;;
        *) fail 'refusing: not a lane scratch dir' ;;
    esac
    rm -rf -- "$lane"
}

[ "$#" -gt 0 ] || { usage; exit 2; }
command=$1
shift
case "$command" in
    init) cmd_init "$@" ;;
    launch) cmd_launch "$@" ;;
    wait) cmd_wait "$@" ;;
    status) cmd_status "$@" ;;
    kill) cmd_kill "$@" ;;
    deadline) cmd_deadline "$@" ;;
    splice-secret) cmd_splice_secret "$@" ;;
    scrub) cmd_scrub "$@" ;;
    rm) cmd_rm "$@" ;;
    -h|--help|*) usage; exit 2 ;;
esac
