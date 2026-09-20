#!/usr/bin/env bash
# Discover XcodeBuildMCP, register it in Codex, and prove its MCP handshake.
set -eu

NAME=xcodebuildmcp
VERSION=2.7.0
WORKFLOWS=simulator,ui-automation,logging
MODE=setup
FORCE=0
LAUNCHER_INPUT=
LAUNCHER_EXPLICIT=0

usage() {
    printf '%s\n' \
        'Usage: scripts/setup-xcodebuildmcp.sh [--check] [--force] [--name <name>] [--version <ver>] [--workflows <list>] [--launcher <path>]' \
        '' \
        '  --check         report present/missing; no changes' \
        '  --force         replace existing block' \
        '  --name <name>   MCP server name (default: xcodebuildmcp)' \
        '  --version <ver> npm version for npx route (default: 2.7.0)' \
        '  --workflows <list>  XCODEBUILDMCP_ENABLED_WORKFLOWS value (default: simulator,ui-automation,logging)' \
        '  --launcher <path>  explicit executable; args become ["mcp"]' \
        '' \
        'Exit codes: 0 done, 1 missing/failed, 2 usage, 3 block present (use --force).' >&2
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
        --check) MODE=check ;;
        --force) FORCE=1 ;;
        --name) shift; [ "$#" -gt 0 ] || { usage; exit 2; }; NAME=$1 ;;
        --version) shift; [ "$#" -gt 0 ] || { usage; exit 2; }; VERSION=$1 ;;
        --workflows) shift; [ "$#" -gt 0 ] || { usage; exit 2; }; WORKFLOWS=$1 ;;
        --launcher) shift; [ "$#" -gt 0 ] || { usage; exit 2; }; LAUNCHER_INPUT=$1; LAUNCHER_EXPLICIT=1 ;;
        -h|--help) usage; exit 2 ;;
        *) usage; exit 2 ;;
    esac
    shift
done

case "$NAME" in
    *[!A-Za-z0-9_-]*|'') fail "server name must be [A-Za-z0-9_-]+: $NAME" 2 ;;
esac

MISSING=0
missing() {
    printf 'MISSING: %s\n' "$1"
    MISSING=1
}

HOST_OK=1
if [ "$(uname -s 2>/dev/null || true)" != Darwin ]; then
    missing "macOS required (XcodeBuildMCP drives Xcode's simulators)"
    HOST_OK=0
else
    XCODE_SELECT_PATH=$(xcode-select -p 2>/dev/null || true)
    if [ -z "$XCODE_SELECT_PATH" ] || [ ! -d "$XCODE_SELECT_PATH" ]; then
        missing 'Xcode command line tools not usable: xcode-select -p did not resolve to an existing directory'
        HOST_OK=0
    elif ! xcrun simctl list devicetypes >/dev/null 2>&1; then
        missing 'Xcode command line tools not usable: xcrun simctl list devicetypes failed'
        HOST_OK=0
    else
        XCODE_VERSION_LINE=$(xcodebuild -version 2>/dev/null | sed -n '1p' || true)
        [ -n "$XCODE_VERSION_LINE" ] && note "xcode: $XCODE_VERSION_LINE"
    fi
fi

LAUNCHER_ROUTE=
MCP_COMMAND_CONFIG=
MCP_COMMAND_EXEC=
MCP_ARGS_TOML=

if [ "$LAUNCHER_EXPLICIT" -eq 1 ]; then
    if [ -x "$LAUNCHER_INPUT" ]; then
        LAUNCHER_ROUTE=explicit
        MCP_COMMAND_CONFIG=$LAUNCHER_INPUT
        MCP_COMMAND_EXEC=$LAUNCHER_INPUT
        MCP_ARGS_TOML='["mcp"]'
        note "launcher: $MCP_COMMAND_CONFIG (explicit)"
    elif [ "$MODE" = check ]; then
        missing "launcher not found or not executable: $LAUNCHER_INPUT"
    else
        fail "launcher not found or not executable: $LAUNCHER_INPUT"
    fi
else
    XCODEBUILDMCP_BIN=$(command -v xcodebuildmcp 2>/dev/null || true)
    if [ -n "$XCODEBUILDMCP_BIN" ] && [ -x "$XCODEBUILDMCP_BIN" ]; then
        LAUNCHER_ROUTE=path
        MCP_COMMAND_CONFIG=$XCODEBUILDMCP_BIN
        MCP_COMMAND_EXEC=$XCODEBUILDMCP_BIN
        MCP_ARGS_TOML='["mcp"]'
        note "launcher: $MCP_COMMAND_CONFIG (PATH)"
    else
        NPX_BIN=$(command -v npx 2>/dev/null || true)
        if [ -n "$NPX_BIN" ] && [ -x "$NPX_BIN" ]; then
            LAUNCHER_ROUTE=npx
            MCP_COMMAND_CONFIG=npx
            MCP_COMMAND_EXEC=$NPX_BIN
            MCP_ARGS_TOML="[\"--yes\", \"xcodebuildmcp@$(printf '%s' "$VERSION" | sed 's/[\\\"]/\\\\&/g')\", \"mcp\"]"
            note "launcher: npx $VERSION"
        else
            missing 'no xcodebuildmcp launcher: install with npm i -g xcodebuildmcp or ensure npx is on PATH'
        fi
    fi
fi

command -v codex >/dev/null 2>&1 || missing 'codex not on PATH'
CODEX_HOME_DIR=${CODEX_HOME:-$HOME/.codex}
CONFIG="$CODEX_HOME_DIR/config.toml"
HEADER="[mcp_servers.$NAME]"
BLOCK_RE="^[[]mcp_servers[.]$NAME([.][^]]*)?[]]"

block_present() {
    [ -f "$CONFIG" ] && grep -qxF "$HEADER" "$CONFIG"
}

print_block() {
    awk -v re="$BLOCK_RE" '
        /^\[/ { p = ($0 ~ re) }
        p { print }' "$CONFIG"
}

toml_string() {
    printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

block_command() {
    print_block | sed -n 's/^command = "\([^"].*\)"$/\1/p' | head -n 1
}

block_args() {
    print_block | sed -n 's/^args = \(.*\)$/\1/p' | head -n 1
}

run_handshake_server() {
    case "$LAUNCHER_ROUTE" in
        npx)
            XCODEBUILDMCP_ENABLED_WORKFLOWS="$WORKFLOWS" run_bounded "$MCP_COMMAND_EXEC" --yes "xcodebuildmcp@$VERSION" mcp
            ;;
        explicit|path)
            XCODEBUILDMCP_ENABLED_WORKFLOWS="$WORKFLOWS" run_bounded "$MCP_COMMAND_EXEC" mcp
            ;;
        *)
            return 1
            ;;
    esac
}

run_bounded() {
    [ -n "$BOUND_4" ] && set -- "$BOUND_4" "$@"
    [ -n "$BOUND_3" ] && set -- "$BOUND_3" "$@"
    [ -n "$BOUND_2" ] && set -- "$BOUND_2" "$@"
    [ -n "$BOUND_1" ] && set -- "$BOUND_1" "$@"
    "$@"
}

resolve_bound() {
    BOUND_1= BOUND_2= BOUND_3= BOUND_4=
    timeout_bin=
    if command -v gtimeout >/dev/null 2>&1; then
        timeout_bin=$(command -v gtimeout)
    else
        timeout_candidate=$(command -v timeout 2>/dev/null || true)
        if [ -n "$timeout_candidate" ] && "$timeout_candidate" --version 2>/dev/null | grep -qi coreutils; then
            timeout_bin=$timeout_candidate
        fi
    fi
    if [ -n "$timeout_bin" ]; then
        BOUND_1=$timeout_bin BOUND_2=-k BOUND_3=5 BOUND_4=90
        note "handshake bound: GNU timeout ($timeout_bin)"
    elif command -v perl >/dev/null 2>&1; then
        BOUND_1=perl BOUND_2=-e BOUND_3='alarm shift @ARGV; exec @ARGV or die "exec: $!"' BOUND_4=90
        note 'handshake bound: perl alarm'
    else
        note 'warning: no GNU timeout or perl found; handshake runs unbounded (macOS: brew install coreutils)'
        note 'handshake bound: none (unbounded)'
    fi
}

verify_handshake() {
    note 'verify: MCP handshake over stdio (initialize, tools/list) with discovered command and args'
    HANDSHAKE=$(mktemp "${TMPDIR:-/tmp}/xcodebuildmcp-handshake.XXXXXX")
    resolve_bound
    {
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"setup-xcodebuildmcp","version":"0"}}}'
        printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
        printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
        i=0
        while [ "$i" -lt 60 ] && ! grep -q '"launch_app_sim"' "$HANDSHAKE" 2>/dev/null; do
            sleep 1
            i=$((i + 1))
        done
    } | run_handshake_server > "$HANDSHAKE" 2>&1 || true

    HANDSHAKE_OK=1
    for required_tool in list_sims snapshot_ui screenshot launch_app_sim; do
        if ! grep -q "\"$required_tool\"" "$HANDSHAKE"; then
            missing "handshake missing tool: $required_tool"
            HANDSHAKE_OK=0
        fi
    done
    if [ "$HANDSHAKE_OK" -eq 1 ]; then
        note 'handshake: ok (list_sims, snapshot_ui, screenshot, launch_app_sim)'
        rm -f -- "$HANDSHAKE"
        return 0
    fi
    missing "handshake (server output kept at $HANDSHAKE)"
    return 1
}

if [ "$MODE" = check ]; then
    if block_present; then
        note "config: $HEADER present in $CONFIG"
        print_block
        if [ -n "$MCP_COMMAND_CONFIG" ]; then
            BLOCK_COMMAND=$(block_command)
            BLOCK_ARGS=$(block_args)
            if [ "$BLOCK_COMMAND" != "$(toml_string "$MCP_COMMAND_CONFIG")" ]; then
                missing "config command ($BLOCK_COMMAND) differs from discovered launcher ($MCP_COMMAND_CONFIG); rerun without --check and with --force to rewrite the block"
            elif [ "$BLOCK_ARGS" != "$MCP_ARGS_TOML" ]; then
                missing "config args ($BLOCK_ARGS) differ from discovered launcher's ($MCP_ARGS_TOML); rerun without --check and with --force to rewrite the block"
            fi
        fi
    else
        missing "$HEADER in $CONFIG"
    fi
    if [ "$HOST_OK" -eq 1 ] && [ -n "$LAUNCHER_ROUTE" ]; then
        verify_handshake || true
    fi
    if [ "$MISSING" -eq 0 ]; then
        note 'CHECK: complete'
        exit 0
    fi
    note 'CHECK: incomplete'
    exit 1
fi

[ "$MISSING" -eq 0 ] || fail 'cannot continue with missing pieces above'

if [ ! -d "$CODEX_HOME_DIR" ]; then
    mkdir -p -- "$CODEX_HOME_DIR" || fail "could not create codex home: $CODEX_HOME_DIR"
fi
if [ ! -f "$CONFIG" ]; then
    : > "$CONFIG" || fail "could not create config: $CONFIG"
fi

if block_present && [ "$FORCE" -eq 0 ]; then
    note "config: $HEADER already present in $CONFIG (rerun with --force to replace):"
    print_block
    exit 3
fi

BACKUP=
if [ -f "$CONFIG" ]; then
    BACKUP="$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    while [ -e "$BACKUP" ]; do
        sleep 1
        BACKUP="$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    done
    cp -- "$CONFIG" "$BACKUP" || fail "could not back up $CONFIG"
    note "config: backup at $BACKUP"
fi

if block_present; then
    TMP=$(mktemp "${TMPDIR:-/tmp}/xcodebuildmcp.XXXXXX")
    awk -v re="$BLOCK_RE" '
        /^\[/ { skip = ($0 ~ re) }
        !skip { print }' "$CONFIG" > "$TMP"
    cat "$TMP" > "$CONFIG"
    rm -f -- "$TMP"
fi

# enabled = false: the lane enables it with -c mcp_servers.xcodebuildmcp.enabled=true.
# default_tools_approval_mode = "approve": Codex 0.153+ requires approval; the lane's approval_policy=never rejects otherwise.
# startup_timeout_sec = 120: a cold npx fetch can take time.
# tool_timeout_sec = 600: build_sim can run for minutes.
{
    if [ -s "$CONFIG" ]; then
        if [ "$(tail -c 1 "$CONFIG" | od -An -c | tr -d ' ')" != '\n' ]; then
            printf '\n'
        fi
        printf '\n'
    fi
    printf '%s\n' "$HEADER"
    printf 'command = "%s"\n' "$(toml_string "$MCP_COMMAND_CONFIG")"
    printf 'args = %s\n' "$MCP_ARGS_TOML"
    printf 'env = { XCODEBUILDMCP_ENABLED_WORKFLOWS = "%s" }\n' "$(toml_string "$WORKFLOWS")"
    printf 'enabled = false\n'
    printf 'required = false\n'
    printf 'default_tools_approval_mode = "approve"\n'
    printf 'startup_timeout_sec = 120\n'
    printf 'tool_timeout_sec = 600\n'
} >> "$CONFIG"
note "config: wrote $HEADER to $CONFIG"

note 'verify: codex parses the block'
codex mcp get "$NAME" >/dev/null 2>&1 || fail "codex mcp get $NAME failed; config.toml may be malformed (backup: ${BACKUP:-none})"

verify_handshake || exit 1

note "DONE. The astra-operator lane enables $NAME per run; nothing else uses it."
