# Fable Advisor

**Fable 5.1 runs the show. Codex does the typing (Luna for routine work, Sol for the hard one-offs, each at the effort the task deserves), Astra drives the browser, and Fable reviews before anything ships.**

> **This is a personal fork** of [DannyMac180/fable-advisor](https://github.com/DannyMac180/fable-advisor) (`upstream`). It adds the detached lane runner (`scripts/lane.sh`), the `astra-operator` browser lane with its `computer-use` skill, the `data-investigator`, `astra-advisor`, and `fable-frontend` lanes, and the operator-owned sandbox posture. Install from this repository (`origin`), not upstream.

<a href="https://github.com/DannyMac180/fable-advisor/raw/main/assets/fable-advisor-demo.mp4"><img src="assets/fable-advisor-demo-poster.png" alt="30-second demo: Fable 5.1 orchestrates, GPT-6 Luna implements, Fable 5.1 reviews" width="100%"></a>

<p align="center"><em>▶ 30s demo — Fable 5.1 orchestrates → GPT-6 Luna implements → Fable 5.1 reviews</em></p>

Claude Code lets every subagent run on a different model, and lets the session run on a different model than its subagents. This plugin uses that for the **architect pattern**: your session runs on **Fable 5.1** as a full-time architect. It owns requirements, decomposition, specs, and verification, routes every implementation task to the right lane at a reasoning effort it names per task, and gets a clean-context **Fable 5.1** review of the finished work before calling anything done.

| Lane | Producer | Invocation | Route here when |
|---|---|---|---|
| Routine | **GPT-6 Luna** | `luna-implementer` agent (default) | The spec fully determines the outcome; Codex does the typing via the [Codex CLI](https://github.com/openai/codex) |
| High-complexity | **GPT-6 Sol** | `sol-implementer` agent | One-off tasks where judgment the spec cannot capture decides the outcome: subtle concurrency, hard debugging, security-sensitive paths, wide refactors |
| Frontend | **Fable 5.1** | `fable-frontend` agent | User-interface code (markup, styles, client-side behavior, charts, tooltips, accessibility) in a clean context: the outcome is judged by what a person sees, which a spec carries poorly and the codex lanes have repeatedly missed; proven by an `astra-operator` browser run and reviewed cross-vendor by `astra-advisor` |
| Review | **Fable 5.1** | `fable-advisor` agent | Commitment boundaries, and **always once at the end**: the advisor reviews the accumulated changes before the architect reports done |
| Review, cross-vendor | **GPT-6 Astra** | `astra-advisor` agent | An independent-family second opinion on a decision, diff, or findings document, read-only, after the Fable review on any deliverable of moderate complexity or above |
| Browser / computer use | **GPT-6 Astra** | `astra-operator` agent | Anything that needs a real browser: UI verification, screenshots, login flows, drag-and-drop, browser E2E, through an isolated headless Playwright Chrome |
| Investigation / data pulls | **Claude Sonnet** | `data-investigator` agent | Read-only queries the architect wrote (SQL against a replica, log-platform queries, API listings), run by the lane and returned as compact tables so raw rows never enter the architect's context |

**Effort is chosen per task.** The architect names `REASONING: low … max` (and `ultra` on Sol) in each spec and every codex lane passes it through; Luna defaults to `high` when the line is missing. The session and the Fable advisor run at whatever `/effort` you set.

Tokens route by capability: Fable emits judgment and specs, the cross-vendor lanes emit the code, and the premium is spent where it changes outcomes: the architecture and the final review. The codex implementation lanes are a different model family than the architect, so cross-vendor review is built into the routing; the `fable-frontend` lane is the one same-family exception and gets its independent check from `astra-advisor` and the browser run. For high-stakes work, run `codex-implementer` and `sol-implementer` on the same spec and let the architect pick the stronger diff.

The plugin ships the **orchestration skill**: the routing doctrine (which lane, which effort), the cost discipline that keeps Fable token volume minimal, the six-part spec contract that makes context-free delegation safe, the verification rules that keep every lane honest, and how to fold in the official [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc) when it is installed.

## Go deeper

I write [**Attention Heads**](https://attentionheads.substack.com/?utm_source=github&utm_medium=readme&utm_campaign=fable-advisor), deep, evidence-backed writing on AI, cognition, and agentic engineering. The **Agentic Engineering Field Notes** series is where I publish practical advice on the craft of using AI. [Subscribe](https://attentionheads.substack.com/subscribe?utm_source=github&utm_medium=readme&utm_campaign=fable-advisor) to get new posts to your inbox.

## Install

```
claude plugin marketplace add raymond-w-ko/fable-advisor
claude plugin install fable-advisor@fable-advisor
```

If you already have the upstream marketplace registered under the same name, remove it first (`claude plugin marketplace remove fable-advisor`) so the install resolves to this fork.

Updating:

```
claude plugin marketplace update fable-advisor
claude plugin update fable-advisor@fable-advisor
```

Then start your session as the architect:

```
/model fable
```

**Lite mode.** Copy [`agents/fable-advisor.md`](agents/fable-advisor.md) into `~/.claude/agents/` and keep your session on Sonnet: advisor consults at commitment boundaries without the orchestration layer (see "Advisor-only mode").

## Requirements

- **Claude Code ≥ 2.1.170** with a subscription that includes Fable 5.1. The agents use the `fable` alias. Without Fable access, change `model: fable` to `model: opus` in `agents/fable-advisor.md` and `agents/fable-frontend.md` and run the session on Opus.
- **The [OpenAI Codex CLI](https://github.com/openai/codex)** installed and authenticated (`npm i -g @openai/codex`, then `codex login`) for every codex-backed lane. `luna-implementer` invokes `gpt-6-luna`, `sol-implementer` invokes `gpt-6-sol`, `astra-advisor` and `astra-operator` invoke `gpt-6-astra`. Without model access or a working CLI a lane reports `STATUS: unavailable`; it never falls back to a Claude model. Without Codex at all, the pattern degrades to advisor-only mode.
- **Sandbox posture.** The implementation lanes pass no `--sandbox` flag and run at the `sandbox_mode` in your `~/.codex/config.toml`. `codex exec` is `read-only` when the key is unset, so set `sandbox_mode = "workspace-write"` there; the lanes' preflight reports `unavailable` until you do. To run the lanes unsandboxed on a disposable machine, type `/fable-advisor:setup-dangerous-yolo-codex` yourself; nothing else in the plugin will run it.
- **The browser lane** needs a Codex MCP server named `playwright_chrome` (headless Playwright Chrome, disabled at rest, enabled by the lane per run). The **`playwright-mcp-setup` skill** creates it on any platform by running `scripts/setup-playwright-mcp.sh`, which first looks for a packaged `playwright-mcp` launcher on PATH (for example, the nixpkgs package), then discovers `node`, `@playwright/mcp`, and Chromium, writes the block with a backup, and proves the server answers an MCP handshake. Run the script with `--check` to see what is missing.
- **The iOS Simulator lane** (macOS only) needs a Codex MCP server named `xcodebuildmcp` ([XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), disabled at rest, enabled by the same `astra-operator` lane per run when a brief targets a simulator). The **`xcodebuildmcp-setup` skill** creates it by running `scripts/setup-xcodebuildmcp.sh`, which checks Xcode, discovers a packaged `xcodebuildmcp` binary or falls back to a pinned `npx`, writes the block with a backup, and proves the server lists the simulator tools. Building and installing the app under test stays with the project's own tooling; the lane drives the installed app and returns screenshots.
- **Optional: the [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc)** (`/plugin marketplace add openai/codex-plugin-cc`, then `/plugin install codex@openai-codex`). The orchestration skill uses `/codex:adversarial-review` as a GPT-family reviewer, `/codex:rescue` as a user-driven delegation path, and `/codex:setup` to diagnose a lane that reports `unavailable`. Not a dependency.
- **Platforms:** Linux, macOS (GNU `timeout` required: `brew install coreutils`, or `pkgs.coreutils-prefixed` on nix-darwin; the lanes refuse to launch without it), and Windows through Git Bash, which Claude Code's Bash tool already uses. WSL works but cannot see a Windows-side `codex`. On Windows the lane script prints lane paths as `C:/...`, kills process trees through `taskkill`, and checks credential files by ACL: lock a secret file with `icacls <file> /inheritance:r /grant:r "%USERNAME%:F"` before naming it in a brief.
- If a pinned Claude model is not available on your account, Claude Code silently falls back to your session model; if advisor verdicts feel unremarkable, check your plan. The codex lanes always fail loudly instead.

Model resolution order in Claude Code: `CLAUDE_CODE_SUBAGENT_MODEL` env var → per-invocation `model` parameter → agent frontmatter → session model. Effort: `CLAUDE_CODE_EFFORT_LEVEL` env var → agent frontmatter `effort` → session `/effort`. None of this plugin's agents set `effort`; the codex lanes take theirs from the spec.

## Use it

With the session on Fable, ask for work; the orchestration skill routes it:

```
Add rate limiting to our public API. Design it, delegate the
implementation, and verify the evidence before you call it done.
```

The architect writes the spec, picks the lane and effort (rate limiting touches concurrency, a case for `sol-implementer` at `max`, or for racing it against `luna-implementer`), reads the diff and verification evidence when the report comes back, sends the finished work to `fable-advisor` and then `astra-advisor`, and only then reports done.

## Lane mechanics

All codex-backed lanes share `scripts/lane.sh`: a private scratch directory per run, detached launch under an 89-minute cap with a kill at 90, bounded `wait`, `status` (with `last_output_age` and `progress_lines` so a lane can tell a stuck run from a slow one; codex appends milestones to `progress.md`, which survives the cap), credential `splice-secret` and `scrub` for the browser lane, `stage-upload` that copies a brief's upload files into the lane so the browser's file chooser can reach them, `rm` when the report is written, and `gc` (also run by `init`) that removes finished lane directories older than 24 hours. Run `bash tests/lane-smoke.sh` to exercise it with a dummy command in seconds. Agents resolve the script through `CLAUDE_PLUGIN_ROOT`, then the plugin cache, then the marketplace checkout.

`scripts/setup-yolo-codex.sh` (behind the user-typed `/fable-advisor:setup-dangerous-yolo-codex` command) has its own smoke test, `bash tests/setup-yolo-codex-smoke.sh`, which runs against temporary config files only.

To make the doctrine always-on, add one line to your project's `CLAUDE.md`:

```
You are the architect — minimize your own token volume. Delegate all
implementation through the orchestration skill's routing table (never
type code yourself), name a reasoning effort per task, delegate broad
codebase exploration to cheap read-only agents, verify evidence before
accepting any lane's report, and get a fable-advisor review before
reporting any deliverable done.
```

## Commitment boundaries and the final review

The `fable-advisor` agent is a read-only skeptic on the same model as the architect but in a clean context: consulted before architecture decisions, migrations, API designs, whenever a problem has resisted two attempts, and **always once at the end of a deliverable**, where it reads the accumulated diff against the stated goal rather than the conversation and returns ship / fix-first / rethink. It never implements. Re-reviews and later increments of the same deliverable go back to the same advisor by `SendMessage`, so its context carries over. For an independent-model review on top, `astra-advisor` runs after it, or the Codex plugin's `/codex:adversarial-review` runs just before it.

## Advisor-only mode

The minimal arrangement: run the session on Sonnet and consult `fable-advisor` only at commitment boundaries.

```
Migrate our checkout sessions from Postgres to Redis — plan it,
consult your advisor before committing, then implement.
```

A typical consult costs cents. To make it automatic, add to your project's `CLAUDE.md`:

```
Before committing to any architecture decision, migration, or refactor
touching 3+ files, consult the fable-advisor agent and act on its verdict.
```

## FAQ

**Is this Anthropic's "advisor tool"?** No, that is a server-side API feature. These are plain Claude Code subagents plus skills: readable, editable, no beta flags.

**Does this work on claude.ai?** No; subagent model routing is Claude Code only (CLI, desktop, VS Code, web).

**Why not let Fable write the code too?** You can. It is also the most expensive model per token, and most of a session's tokens are implementation mechanics that the codex lanes handle at near parity, from a different vendor, which buys a real second opinion. Spend the premium where it changes outcomes. The one built-in exception is user-interface code: the `fable-frontend` lane runs Fable in a clean context because visual and interaction judgment does not survive translation into a spec, and the cross-vendor check moves to the Astra review and the browser run.

**Why GPT lanes in a Claude plugin?** Vendor diversity. Models from one family share blind spots; an independent implementation from a different lineage catches what same-family review misses. The architect and reviewer stay Claude; the lanes are producers, not judges.

**Which Luna effort?** `high` by default. Luna's per-token price is nearly flat across the ladder, so `max` costs little money, but it roughly doubles wall-clock and consumes context faster on long runs; use it for a second attempt or when the spec names an algorithm the lane must get right first time, and keep every Luna spec to one coherent change with one verification command.

**Older lanes.** A Claude implementation lane (`fable-implementer`) exists in the [v4.0 tree](https://github.com/DannyMac180/fable-advisor/blob/ad2bdc3/agents/fable-implementer.md) and a Grok lane in the [v3.1 tree](https://github.com/DannyMac180/fable-advisor/blob/b3b50a9/agents/grok-implementer.md) upstream.

## License

MIT
