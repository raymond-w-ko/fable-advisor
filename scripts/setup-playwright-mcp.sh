#!/usr/bin/env bash
# Discover a packaged launcher or node and npm, register the server in
# ~/.codex/config.toml under the name the astra-operator lane expects, and prove
# it answers an MCP handshake. Nothing is hard-coded: every path comes from the
# host. Works on Linux, macOS, and Git Bash on Windows.
set -eu

NAME=playwright_chrome
MODE=setup
FORCE=0
SKIP_BROWSER=0
LAUNCHER_INPUT=
LAUNCHER_EXPLICIT=0
STARTUP_TIMEOUT=60
TOOL_TIMEOUT=120

usage() {
    printf '%s\n' \
        'Usage: scripts/setup-playwright-mcp.sh [--check] [--force] [--skip-browser] [--launcher <path>] [--name <server-name>]' \
        '' \
        '  --check         report what is present and what is missing; change nothing' \
        '  --force         replace an existing [mcp_servers.<name>] block' \
        '  --skip-browser  do not run "playwright install chromium"' \
        '  --launcher <path>  use this packaged MCP launcher executable' \
        '  --name <name>   MCP server name (default: playwright_chrome)' \
        '' \
        'Exit codes: 0 done, 1 something missing (--check) or a step failed,' \
        '            2 usage, 3 block already present (rerun with --force).' >&2
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
        --skip-browser) SKIP_BROWSER=1 ;;
        --launcher) shift; [ "$#" -gt 0 ] || { usage; exit 2; }; LAUNCHER_INPUT=$1; LAUNCHER_EXPLICIT=1 ;;
        --name) shift; [ "$#" -gt 0 ] || { usage; exit 2; }; NAME=$1 ;;
        -h|--help) usage; exit 2 ;;
        *) usage; exit 2 ;;
    esac
    shift
done

case "$NAME" in
    *[!A-Za-z0-9_-]*|'') fail "server name must be [A-Za-z0-9_-]+: $NAME" 2 ;;
esac

case $(uname -s 2>/dev/null) in
    MINGW*|MSYS*|CYGWIN*) IS_MSYS=1 ;;
    *) IS_MSYS=0 ;;
esac

# Path as bash sees it (for tests) and as the host's native tools see it (for config).
to_bash_path() {
    if [ "$IS_MSYS" -eq 1 ]; then cygpath -u -- "$1"; else printf '%s\n' "$1"; fi
}

to_host_path() {
    if [ "$IS_MSYS" -eq 1 ]; then cygpath -m -- "$1"; else printf '%s\n' "$1"; fi
}

MISSING=0
missing() {
    printf 'MISSING: %s\n' "$1"
    MISSING=1
}

PACKAGED=0
LAUNCHER_BASH=
LAUNCHER_HOST=
MCP_COMMAND_HOST=
MCP_ARG0_HOST=
MCP_HEADLESS_ARG=--headless
MCP_ISOLATED_ARG=--isolated

# --- packaged launcher ------------------------------------------------------
if [ "$LAUNCHER_EXPLICIT" -eq 1 ]; then
    LAUNCHER_BASH=$(to_bash_path "$LAUNCHER_INPUT")
    if [ -x "$LAUNCHER_BASH" ]; then
        PACKAGED=1
    elif [ "$MODE" = check ]; then
        missing "launcher not found or not executable: $LAUNCHER_INPUT"
    else
        fail "launcher not found or not executable: $LAUNCHER_INPUT"
    fi
else
    for candidate_name in playwright-mcp mcp-server-playwright; do
        candidate=$(command -v "$candidate_name" 2>/dev/null || true)
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            LAUNCHER_BASH=$candidate
            PACKAGED=1
            break
        fi
    done
fi

if [ "$PACKAGED" -eq 1 ]; then
    LAUNCHER_HOST=$(to_host_path "$LAUNCHER_BASH")
    MCP_COMMAND_HOST=$LAUNCHER_HOST
    note "launcher: $LAUNCHER_HOST (packaged; expected to bring its own Playwright and Chromium, which the handshake does not launch)"
fi

if [ "$PACKAGED" -eq 0 ] && [ "$LAUNCHER_EXPLICIT" -eq 0 ]; then
    # --- node ----------------------------------------------------------------
    NODE_BIN=$(command -v node 2>/dev/null || true)
    [ -n "$NODE_BIN" ] || fail 'node not on PATH (Node.js 18 or later is required)'
    NODE_VERSION=$(node --version 2>/dev/null | tr -d 'v\r')
    NODE_MAJOR=${NODE_VERSION%%.*}
    [ "${NODE_MAJOR:-0}" -ge 18 ] || fail "node $NODE_VERSION is too old; 18 or later is required"
    NODE_HOST=$(to_host_path "$NODE_BIN")
    note "node: $NODE_HOST (v$NODE_VERSION)"

    command -v npm >/dev/null 2>&1 || fail 'npm not on PATH'
    GLOBAL_ROOT_RAW=$(npm root -g 2>/dev/null | tr -d '\r')
    [ -n "$GLOBAL_ROOT_RAW" ] || fail 'npm root -g returned nothing'
    GLOBAL_ROOT=$(to_bash_path "$GLOBAL_ROOT_RAW")
    note "npm global root: $(to_host_path "$GLOBAL_ROOT")"

    # --- @playwright/mcp ----------------------------------------------------
    MCP_CLI="$GLOBAL_ROOT/@playwright/mcp/cli.js"
    if [ ! -f "$MCP_CLI" ]; then
        if [ "$MODE" = check ]; then
            case "$GLOBAL_ROOT" in
                /nix/store/*)
                    missing '@playwright/mcp (npm global root is in the Nix store; add pkgs.playwright-mcp to the system or home packages and rerun, or pass --launcher <path>)' ;;
                *)
                    missing '@playwright/mcp (npm install -g @playwright/mcp; if the global root is read-only, as with Nix or a system node, set a user prefix first: npm config set prefix ~/.npm-global)' ;;
            esac
        else
            note 'installing @playwright/mcp globally'
            npm install -g @playwright/mcp >/dev/null || fail 'npm install -g @playwright/mcp failed'
            [ -f "$MCP_CLI" ] || fail "install ran but $MCP_CLI is still missing"
        fi
    fi
    if [ -f "$MCP_CLI" ]; then
        MCP_VERSION=$(node -e 'console.log(require(process.argv[1]).version)' "$(to_host_path "$GLOBAL_ROOT")/@playwright/mcp/package.json" 2>/dev/null || echo '?')
        note "@playwright/mcp: $(to_host_path "$MCP_CLI") ($MCP_VERSION)"
    fi

    # --- Chromium -----------------------------------------------------------
    # @playwright/mcp bundles playwright-core, whose cli.js installs browsers.
    # Its location depends on how npm hoisted the dependency.
    PW_CLI=
    for candidate in \
        "$GLOBAL_ROOT/@playwright/mcp/node_modules/playwright-core/cli.js" \
        "$GLOBAL_ROOT/playwright-core/cli.js" \
        "$GLOBAL_ROOT/playwright/cli.js"; do
        if [ -f "$candidate" ]; then
            PW_CLI=$candidate
            break
        fi
    done

    if [ -f "$MCP_CLI" ]; then
        if [ -z "$PW_CLI" ]; then
            missing 'playwright-core/cli.js next to @playwright/mcp (reinstall @playwright/mcp)'
        elif [ "$SKIP_BROWSER" -eq 1 ]; then
            note 'chromium: skipped (--skip-browser)'
        elif [ "$MODE" = check ]; then
            # --dry-run prints each component's install location; present means the directory exists.
            BROWSER_MISSING=0
            while IFS= read -r location; do
                [ -n "$location" ] || continue
                [ -d "$(to_bash_path "$location")" ] || BROWSER_MISSING=1
            done <<EOF
$(node "$PW_CLI" install --dry-run chromium 2>/dev/null | sed -n 's/^ *Install location: *//p' | tr -d '\r')
EOF
            if [ "$BROWSER_MISSING" -eq 1 ]; then
                missing "chromium for playwright (node $(to_host_path "$PW_CLI") install chromium)"
            else
                note 'chromium: present'
            fi
        else
            note 'chromium: running playwright install chromium (no-op when present)'
            node "$PW_CLI" install chromium >/dev/null || fail 'playwright install chromium failed'
            note 'chromium: present'
        fi
    fi

    MCP_COMMAND_HOST=$NODE_HOST
    if [ -f "$MCP_CLI" ]; then
        MCP_ARG0_HOST=$(to_host_path "$MCP_CLI")
    fi
fi

# --- codex ------------------------------------------------------------------
command -v codex >/dev/null 2>&1 || fail 'codex not on PATH'
CODEX_HOME_DIR=${CODEX_HOME:-$HOME/.codex}
CONFIG="$CODEX_HOME_DIR/config.toml"
[ -d "$CODEX_HOME_DIR" ] || fail "codex home missing: $CODEX_HOME_DIR (run codex login first)"
HEADER="[mcp_servers.$NAME]"
# Matches the block header and its subtables ([mcp_servers.<name>.env] and so on).
# Bracket classes instead of backslashes: awk -v rewrites escape sequences.
BLOCK_RE="^[[]mcp_servers[.]$NAME([.][^]]*)?[]]"

block_present() {
    [ -f "$CONFIG" ] && grep -qxF "$HEADER" "$CONFIG"
}

# The block and its subtables, wherever they sit; other tables in between are skipped.
print_block() {
    awk -v re="$BLOCK_RE" '
        /^\[/ { p = ($0 ~ re) }
        p { print }' "$CONFIG"
}

# TOML basic strings: escape backslash and double quote (Windows paths are
# already forward-slash form, so this only matters for unusual POSIX paths).
toml_string() {
    printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

if [ "$PACKAGED" -eq 1 ]; then
    MCP_ARGS_TOML="[\"$(toml_string "$MCP_HEADLESS_ARG")\", \"$(toml_string "$MCP_ISOLATED_ARG")\"]"
elif [ -n "$MCP_ARG0_HOST" ]; then
    MCP_ARGS_TOML="[\"$(toml_string "$MCP_ARG0_HOST")\", \"$(toml_string "$MCP_HEADLESS_ARG")\", \"$(toml_string "$MCP_ISOLATED_ARG")\"]"
else
    MCP_ARGS_TOML=
fi

block_command() {
    print_block | sed -n 's/^command = "\([^"]*\)".*/\1/p' | head -n 1
}

block_args() {
    print_block | sed -n 's/^args = \(.*\)$/\1/p' | head -n 1
}

# Host-form paths, exactly what the block carries (node.exe accepts C:/ paths).
run_handshake_server() {
    if [ -n "$MCP_ARG0_HOST" ]; then
        "$timeout_bin" -k 5 90 "$MCP_COMMAND_HOST" "$MCP_ARG0_HOST" "$MCP_HEADLESS_ARG" "$MCP_ISOLATED_ARG"
    else
        "$timeout_bin" -k 5 90 "$MCP_COMMAND_HOST" "$MCP_HEADLESS_ARG" "$MCP_ISOLATED_ARG"
    fi
}

verify_handshake() {
    note 'verify: MCP handshake over stdio (initialize, tools/list) with discovered command and args'
    HANDSHAKE=$(mktemp "${TMPDIR:-/tmp}/playwright-mcp-handshake.XXXXXX")
    timeout_bin=
    for candidate in gtimeout timeout; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" --version 2>/dev/null | grep -qi coreutils; then
            timeout_bin=$candidate
            break
        fi
    done
    [ -n "$timeout_bin" ] || fail 'GNU timeout not found; the handshake cannot be bounded (macOS: brew install coreutils)'
    {
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"setup-playwright-mcp","version":"0"}}}'
        printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
        printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
        # Hold stdin open until the reply lands (slow cold hosts), at most 60 s.
        i=0
        while [ "$i" -lt 60 ] && ! grep -q '"browser_navigate"' "$HANDSHAKE" 2>/dev/null; do
            sleep 1
            i=$((i + 1))
        done
    } | run_handshake_server > "$HANDSHAKE" 2>&1 || true
    if grep -q '"browser_navigate"' "$HANDSHAKE"; then
        note "handshake: ok ($(grep -o '"name":"browser_[a-z_]*"' "$HANDSHAKE" | wc -l | tr -d ' ') browser tools)"
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
        if [ -n "$MCP_COMMAND_HOST" ]; then
            # The handshake below runs the discovered launcher, so it only vouches
            # for the block when the block carries the same command and args.
            BLOCK_COMMAND=$(block_command)
            BLOCK_ARGS=$(block_args)
            if [ "$BLOCK_COMMAND" != "$MCP_COMMAND_HOST" ]; then
                missing "config command ($BLOCK_COMMAND) differs from discovered launcher ($MCP_COMMAND_HOST); rerun without --check and with --force to rewrite the block"
            elif [ "$BLOCK_ARGS" != "$MCP_ARGS_TOML" ]; then
                missing "config args ($BLOCK_ARGS) differ from the discovered launcher's ($MCP_ARGS_TOML); rerun without --check and with --force to rewrite the block"
            fi
        fi
    else
        missing "$HEADER in $CONFIG"
    fi
    if [ "$PACKAGED" -eq 1 ] || [ -n "$MCP_ARG0_HOST" ]; then
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

if block_present && [ "$FORCE" -eq 0 ]; then
    note "config: $HEADER already present in $CONFIG (rerun with --force to replace):"
    print_block
    exit 3
fi

BACKUP="$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
if [ -f "$CONFIG" ]; then
    cp -- "$CONFIG" "$BACKUP"
    note "config: backup at $BACKUP"
fi

if block_present; then
    # Drop the old block and its subtables; every other table stays.
    TMP=$(mktemp "${TMPDIR:-/tmp}/playwright-mcp.XXXXXX")
    awk -v re="$BLOCK_RE" '
        /^\[/ { skip = ($0 ~ re) }
        !skip { print }' "$CONFIG" > "$TMP"
    cat "$TMP" > "$CONFIG"
    rm -f -- "$TMP"
fi

# Forward slashes keep the TOML free of escapes; node.exe accepts them on Windows.
# enabled = false at rest: the lane turns the server on per run with
# -c mcp_servers.<name>.enabled=true and never leaks a browser into other sessions.
# default_tools_approval_mode = "approve": since codex 0.153 every MCP tool call
# is an approval request, and the lane's approval_policy="never" auto-rejects
# it ("MCP tool call requires approval, but approval policy is never"). "auto"
# is not enough because the Playwright tools carry no read-only annotations.
# Packaged launchers run directly; node + cli.js rather than npx: npx.cmd
# deadlocks on piped stdin on Windows.
{
    if [ -s "$CONFIG" ] && [ "$(tail -c 1 "$CONFIG" | od -An -c | tr -d ' ')" != '\n' ]; then
        printf '\n'
    fi
    printf '\n%s\n' "$HEADER"
    printf 'command = "%s"\n' "$(toml_string "$MCP_COMMAND_HOST")"
    printf 'args = %s\n' "$MCP_ARGS_TOML"
    printf 'enabled = false\n'
    printf 'default_tools_approval_mode = "approve"\n'
    printf 'startup_timeout_sec = %s\n' "$STARTUP_TIMEOUT"
    printf 'tool_timeout_sec = %s\n' "$TOOL_TIMEOUT"
} >> "$CONFIG"
note "config: wrote $HEADER to $CONFIG"

# --- verify -----------------------------------------------------------------
note 'verify: codex parses the block'
codex mcp get "$NAME" >/dev/null 2>&1 || fail "codex mcp get $NAME failed; config.toml may be malformed (backup: ${BACKUP:-none})"

verify_handshake || exit 1

note 'DONE. The astra-operator lane enables this server per run; nothing else uses it.'
