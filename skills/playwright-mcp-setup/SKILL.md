---
name: playwright-mcp-setup
description: Install and register the headless Playwright Chrome MCP server that the `astra-operator` browser lane requires, on Linux, macOS, or Git Bash on Windows. Runs `scripts/setup-playwright-mcp.sh`, which discovers node, npm's global root, `@playwright/mcp`, and Playwright's Chromium on the host (nothing hard-coded), writes `[mcp_servers.playwright_chrome]` to `~/.codex/config.toml` with a backup, and proves the server answers an MCP handshake. USE WHEN `astra-operator` returns `STATUS: unavailable` with `playwright_chrome not configured`, when the user asks to set up Playwright MCP or the browser lane for Codex, when checking whether the browser lane is ready on a new machine, or when a Windows host needs the node-not-npx launcher form.
---

# Playwright MCP setup — make the browser lane available

The `astra-operator` agent enables a Codex MCP server named exactly `playwright_chrome` per run. This plugin never creates that server; the host must. This skill does it once per machine, by discovery, and verifies the result.

## Run the script

Resolve the plugin root the way the agents do, then run the script. Use the Bash tool on every platform, including Windows, where Claude Code's Bash tool already runs Git Bash.

```bash
SETUP="${CLAUDE_PLUGIN_ROOT:-}/scripts/setup-playwright-mcp.sh"
[ -f "$SETUP" ] || SETUP=$(ls -d "$HOME"/.claude/plugins/cache/fable-advisor/fable-advisor/*/scripts/setup-playwright-mcp.sh 2>/dev/null | sort -V | tail -1)
[ -f "$SETUP" ] || SETUP="$HOME/.claude/plugins/marketplaces/fable-advisor/scripts/setup-playwright-mcp.sh"
[ -f "$SETUP" ] || { echo "setup-playwright-mcp.sh not found; plugin install is incomplete"; exit 2; }

bash "$SETUP" --check    # report only, changes nothing
bash "$SETUP"            # install what is missing, write the block, verify
```

Set the Bash tool's `timeout` to 600000 ms for the real run: a first-time Chromium download can take minutes.

Exit codes:

| Code | Meaning | What to do |
|---|---|---|
| 0 | done and verified, or `--check` found everything | Report the block it printed. |
| 1 | `--check` found something missing, or a step failed | Read the `MISSING:` or `ERROR:` line; it names the fix. A handshake failure keeps the server output in a file whose path is printed. |
| 2 | usage error | Fix the arguments. |
| 3 | `[mcp_servers.playwright_chrome]` already exists | Show the user the printed block. Rerun with `--force` only if they want it replaced; the old file is backed up next to it as `config.toml.bak.<timestamp>`. |

Flags: `--force` replaces an existing block, `--skip-browser` skips `playwright install chromium`, `--name <name>` registers under another server name (the lane expects `playwright_chrome`; use another name only when the user says so).

## What the script discovers

- `node` on PATH, version 18 or later. On Windows the config gets the `C:/...` form of the path.
- `npm root -g`, then `@playwright/mcp/cli.js` under it. Installs the package globally when absent.
- `playwright-core/cli.js` wherever npm hoisted it, then `install chromium` through it. Idempotent.
- `codex` on PATH and `${CODEX_HOME:-~/.codex}/config.toml`.

It writes this shape, with the discovered paths:

```toml
[mcp_servers.playwright_chrome]
command = "<node>"
args = ["<npm global root>/@playwright/mcp/cli.js", "--headless", "--isolated"]
enabled = false
default_tools_approval_mode = "approve"
startup_timeout_sec = 60
tool_timeout_sec = 120
```

`enabled = false` at rest is deliberate: only the lane turns the server on, with `-c mcp_servers.playwright_chrome.enabled=true`, so no other Codex session grows a browser. `--isolated` keeps the profile in memory. The startup timeout is raised from Codex's 10 s default because a cold Chromium launch on Windows can exceed it.

`default_tools_approval_mode = "approve"` is what makes the lane work at all on Codex 0.153 and later: every MCP tool call is an approval request there, and the lane runs with `approval_policy="never"`, which auto-rejects instead of asking. The symptom without it is a run that ends rc=0 with `MCP tool call requires approval, but approval policy is never` in the events and no navigation. `auto` does not help because the Playwright tools carry no read-only annotations. The `astra-operator` agent also passes the same key with `-c` per run, so an older block written by hand still works once the agent is current.

## Why node plus cli.js, not npx

On Windows, `npx` is `npx.cmd`, a batch wrapper. Spawned as a stdio MCP server it deadlocks on piped stdin even with `-y`, and `cmd /c npx` loses the pipes entirely. Launching `node` on the package's `cli.js` avoids both. The same form works on Linux and macOS, so the script uses it everywhere; do not rewrite the block to `npx`.

## Verification the script performs

1. `codex mcp get playwright_chrome` parses the block.
2. A stdio handshake (`initialize`, `notifications/initialized`, `tools/list`) against the exact command and args in the block must list `browser_navigate`.

For a full end-to-end check, run the `astra-operator` agent with a brief against a URL the user authorizes, for example a public page or a local dev server, and confirm it returns screenshots from `$LANE/shots`. Do that only when the user wants the cost of a GPT-6 Astra run.

## Not this skill

- Driving the browser: that is the `computer-use` skill and the `astra-operator` agent.
- Codex's bundled `browser` and `chrome` plugins and its `browser_use` feature: those are the ChatGPT in-app browser and the user's own Chrome, driven through `node_repl`, not an MCP server the lane can enable by name.
- Headed or real-Chrome sessions: change `args` by hand if the user wants `--browser chrome` or no `--headless`; the lane's doctrine assumes headless and isolated.
