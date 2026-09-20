---
name: xcodebuildmcp-setup
description: Register the XcodeBuildMCP server that the `astra-operator` lane needs to drive an iOS Simulator (build, install, launch, accessibility snapshot, tap, type, screenshot) through Codex on macOS. Runs `scripts/setup-xcodebuildmcp.sh`, which checks Xcode, discovers a packaged `xcodebuildmcp` binary or falls back to `npx`, writes `[mcp_servers.xcodebuildmcp]` to `~/.codex/config.toml` with a backup, and proves the server answers an MCP handshake listing the simulator tools. USE WHEN `astra-operator` returns `STATUS: unavailable` with `xcodebuildmcp not configured`, when the user asks to set up iOS Simulator automation or XcodeBuildMCP for Codex, or when checking whether the iOS lane is ready on a new Mac.
---

# XcodeBuildMCP setup — make the iOS Simulator lane available

The `astra-operator` agent enables a Codex MCP server named exactly `xcodebuildmcp` per run when a brief targets an iOS Simulator. This plugin never creates that server; the host must. This skill does it once per Mac, by discovery, and verifies the result. Linux and Windows hosts cannot run this lane: XcodeBuildMCP drives Xcode's own simulators.

## Run the script

Resolve the plugin root the way the agents do, then run the script.

```bash
SETUP="${CLAUDE_PLUGIN_ROOT:-}/scripts/setup-xcodebuildmcp.sh"
[ -f "$SETUP" ] || SETUP=$(ls -d "$HOME"/.claude/plugins/cache/fable-advisor/fable-advisor/*/scripts/setup-xcodebuildmcp.sh 2>/dev/null | sort -V | tail -1)
[ -f "$SETUP" ] || SETUP="$HOME/.claude/plugins/marketplaces/fable-advisor/scripts/setup-xcodebuildmcp.sh"
[ -f "$SETUP" ] || { echo "setup-xcodebuildmcp.sh not found; plugin install is incomplete"; exit 2; }

bash "$SETUP" --check    # report only, changes nothing
bash "$SETUP"            # write the block, verify
```

Set the Bash tool's `timeout` to 600000 ms for the real run: on the `npx` route the first handshake downloads the package.

Exit codes:

| Code | Meaning | What to do |
|---|---|---|
| 0 | done and verified, or `--check` found everything | Report the block it printed. |
| 1 | `--check` found something missing, or a step failed | Read the `MISSING:` or `ERROR:` line; it names the fix. |
| 2 | usage error | Fix the arguments. |
| 3 | `[mcp_servers.xcodebuildmcp]` already exists | Show the user the printed block. Rerun with `--force` only if they want it replaced; the old file is backed up next to it as `config.toml.bak.<timestamp>`. |

Flags: `--force` replaces an existing block, `--version <ver>` pins another `xcodebuildmcp` npm version for the `npx` route (default `2.7.0`, the first release with Xcode 27 Device Hub support), `--workflows <list>` changes the tool set the server exposes, `--launcher <path>` selects an explicit `xcodebuildmcp` executable, and `--name <name>` registers under another server name (the lane expects `xcodebuildmcp`; use another name only when the user says so).

## What the script discovers

- macOS, then Xcode: `xcode-select -p` must resolve and `xcrun simctl list devicetypes` must succeed. It prints the `xcodebuild -version` line so the user can see which Xcode the server will drive. It never installs Xcode, runtimes, or simulators.
- A launcher: `--launcher <path>` if given, else an `xcodebuildmcp` executable on PATH (a global `npm i -g xcodebuildmcp` or a packaged install), else `npx`. The packaged route runs the binary directly with `args = ["mcp"]`; the `npx` route pins the version so every run resolves the same package from the npm cache.
- `codex` on PATH and `${CODEX_HOME:-~/.codex}/config.toml`.

For the `npx` route it writes exactly this:

```toml
[mcp_servers.xcodebuildmcp]
command = "npx"
args = ["--yes", "xcodebuildmcp@2.7.0", "mcp"]
env = { XCODEBUILDMCP_ENABLED_WORKFLOWS = "simulator,ui-automation,logging" }
enabled = false
required = false
default_tools_approval_mode = "approve"
startup_timeout_sec = 120
tool_timeout_sec = 600
```

For the packaged route, `command` is the launcher path and `args = ["mcp"]`; the rest is identical.

Why each line matters:

- `enabled = false` at rest is deliberate: only the lane turns the server on, with `-c mcp_servers.xcodebuildmcp.enabled=true -c mcp_servers.xcodebuildmcp.required=true`, so no other Codex session grows an Xcode toolchain and its 60-odd tools.
- `XCODEBUILDMCP_ENABLED_WORKFLOWS` limits the tool list to what the lane uses: simulator lifecycle, build/install/launch, UI automation (`snapshot_ui`, `tap`, `type_text`, `swipe`, `screenshot`, `record_sim_video`), and log capture. The default leaves out LLDB debugging and device workflows; pass `--workflows` to add them when a brief needs them.
- `default_tools_approval_mode = "approve"` is what makes the lane work at all on Codex 0.153 and later: every MCP tool call is an approval request there, and the lane runs with `approval_policy="never"`, which auto-rejects instead of asking. The symptom without it is a run that ends rc=0 with `MCP tool call requires approval, but approval policy is never` in the events and no simulator activity. The `astra-operator` agent also passes the same key with `-c` per run.
- `tool_timeout_sec = 600` because `build_sim` and `boot_sim` run for minutes; Codex's 60 s default aborts them mid-build.
- `startup_timeout_sec = 120` covers a cold `npx` resolution.

## Sandbox facts the lane relies on

Verified on macOS with Codex 0.155 and Xcode 27.1:

- The MCP server is spawned by Codex outside the sandbox, so `xcodebuild`, `simctl`, and AXe run with the user's full permissions even when the run itself is `-s workspace-write`. That is why the lane does not need `danger-full-access` for iOS work.
- The sandboxed shell inside the run cannot reach CoreSimulator: `xcrun simctl ... screenshot` fails there with `CoreSimulatorService connection became invalid`. Evidence therefore comes from the MCP tools, never from shell `simctl` calls made by the model: `screenshot` with `returnFormat: "path"` makes the server write the file and return its path, `record_sim_video` with `outputFile` writes an MP4, and every `screenshot` result also lands as base64 in the run's JSONL events, from which the lane can recover an image when a path is missing.

## Verification the script performs

1. `codex mcp get xcodebuildmcp` parses the block.
2. A stdio handshake (`initialize`, `notifications/initialized`, `tools/list`) against the exact command, args, and env in the block must list `list_sims`, `snapshot_ui`, `screenshot`, and `launch_app_sim`. `--check` also runs this handshake when it finds a launcher, and reports `MISSING:` when the existing block's `command` or `args` differ from what the script would write now; rerun without `--check` and with `--force` to rewrite it.

For a full end-to-end check, run the `astra-operator` agent with an iOS brief against a booted simulator and an installed app the user authorizes, and confirm it returns screenshot paths in `EVIDENCE`. Do that only when the user wants the cost of a GPT-6 Astra run.

## Not this skill

- Building and installing the app under test: that is the project's own build tooling, run by the architect or an implementation lane before the brief is written; the `computer-use` skill's iOS section says what the brief must carry.
- Driving the simulator: that is the `computer-use` skill and the `astra-operator` agent.
- Apple's own `xcrun mcpbridge` server (Xcode 26.3 and later): build diagnostics and previews, no tap or type. It can sit alongside `xcodebuildmcp` in `config.toml` but is not what the lane enables.
- Physical devices: XcodeBuildMCP has a device workflow, but the lane's doctrine assumes a simulator; add `device` to `--workflows` and write a device brief only when the user asks.
