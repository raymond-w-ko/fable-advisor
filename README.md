# Fable Advisor

**Fable 5.1 runs the show. Codex does the typing (Luna always at max, Sol at the effort each task deserves), Astra drives the browser, and Fable reviews before anything ships.**

> **This is a personal fork** of [DannyMac180/fable-advisor](https://github.com/DannyMac180/fable-advisor) (`upstream`). It carries the v5.1 lane hardening (zsh-safe timeout wrapper, per-lane scratch dirs, sandbox and IPC-mismatch handling, working-directory pinning) and the **`astra-operator`** browser/computer-use lane with its **`computer-use`** skill. Install from this repository (`origin`), not upstream, to get them.

<a href="https://github.com/DannyMac180/fable-advisor/raw/main/assets/fable-advisor-demo.mp4"><img src="assets/fable-advisor-demo-poster.png" alt="30-second demo: Fable 5.1 orchestrates, GPT-5.6 Luna implements, Fable 5.1 reviews" width="100%"></a>

<p align="center"><em>▶ 30s demo — Fable 5.1 orchestrates → GPT-5.6 Luna implements → Fable 5.1 reviews</em></p>

Claude Code lets every subagent run on a different model — and lets the session itself run on a different model than its subagents. This plugin exploits that with the **architect pattern**: your session runs on **Fable 5.1**, acting as a full-time architect. It owns requirements, decomposition, specs, and verification — routes every implementation task to the right lane (Luna always at `max`, Sol at a reasoning effort chosen per task) — and gets a clean-context **Fable 5.1** review of the finished work before calling anything done:

| Lane | Producer | Invocation | Route here when |
|---|---|---|---|
| Routine | **GPT-5.6 Luna**, always at `max` | `codex-implementer` agent (default) | The spec fully determines the outcome — Codex does the typing via the [Codex CLI](https://github.com/openai/codex) |
| High-complexity | **GPT-5.6 Sol** | `sol-implementer` agent | One-off tasks where judgment the spec can't capture decides the outcome: subtle concurrency, hard debugging, security-sensitive paths, wide refactors |
| Review | **Fable 5.1** | `fable-advisor` agent | Commitment boundaries, and **always once at the end** — the advisor reviews the accumulated changes before the architect reports done |
| Browser / computer use | **GPT-6 Astra** | `astra-operator` agent | Any task that needs a real browser — UI verification, screenshots, login flows, drag-and-drop, browser E2E. Astra drives an isolated headless Playwright Chrome through the Codex CLI; the `computer-use` skill carries the doctrine. |
| Investigation / data pulls | **Claude Sonnet** | `data-investigator` agent | Read-only queries the architect wrote — SQL against a replica, log-platform queries, API listings — run by the lane, written to files, returned as compact tables so raw rows never enter the architect's context. |
| Review, cross-vendor | **GPT-6 Astra** | `astra-advisor` agent | An independent-family second opinion on a decision, diff, or findings document, run read-only through the Codex CLI at a chosen effort. Runs automatically after the Fable review on any deliverable of moderate complexity or above; it complements the Fable review and never replaces it. |

**Luna is pinned at `max`; everything else is chosen per task.** The routine lane always runs GPT-5.6 Luna at `max` — Luna bills the same per-token rate at every effort, the whole ladder from `low` to `max` costs about three cents more per task, and the lane is never on the interactive path, so every point of intelligence is worth buying (see the v5.4 FAQ entry for the numbers and sources). For Sol and the Astra advisor the architect names the effort per task in the spec (`REASONING: low … max`, and `ultra` on Sol), and the lanes pass it through unchanged. The session and the Fable advisor run at whatever `/effort` you set.

Tokens route by capability: Fable emits judgment and specs, the cross-vendor lanes emit all of the code, and the premium is spent only where it changes outcomes: the architecture and the final review. Because both implementation lanes are a *different model family* than the architect, cross-vendor review is built into the routing, not bolted on. For high-stakes work, run `codex-implementer` and `sol-implementer` on the same spec and let the architect pick the stronger diff.

The plugin ships the **orchestration skill** — the routing doctrine that teaches the session when to use each lane and each effort rung, the cost discipline that keeps Fable token volume minimal (emit judgment not volume, keep context lean, reason once then hand off), the six-part spec contract that makes context-free delegation safe, the verification rules that keep every lane honest, and how to fold in the official [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc) when it's installed.

## Go deeper

I write [**Attention Heads**](https://attentionheads.substack.com/?utm_source=github&utm_medium=readme&utm_campaign=fable-advisor) — deep, evidence-backed writing on AI, cognition, and agentic engineering. The **Agentic Engineering Field Notes** series is where I publish practical advice on the craft of using AI. [Subscribe](https://attentionheads.substack.com/subscribe?

## Install

```
claude plugin marketplace add raymond-w-ko/fable-advisor
claude plugin install fable-advisor@fable-advisor
```

If you already have the upstream marketplace registered under the same name, remove it first (`claude plugin marketplace remove fable-advisor`) so the install resolves to this fork.

Updating an existing installation to the latest release:

```
claude plugin marketplace update fable-advisor
claude plugin update fable-advisor@fable-advisor
```

Then start your session as the architect:

```
/model fable
```

**Lite mode — one file, 30 seconds.** Don't want the full pattern? Copy [`agents/fable-advisor.md`](agents/fable-advisor.md) into `~/.claude/agents/` and keep your session on Sonnet. You get advisor consults at commitment boundaries without the orchestration layer (see "Advisor-only mode" below).

## Requirements

- **Claude Code ≥ 2.1.170** with a subscription that includes Fable 5.1 (Pro, Max, Team, or Enterprise — all current consumer plans qualify). The agents use the `fable` alias, which resolves to Fable 5.1.
- **No Fable access** (e.g. API-key billing)? Change `model: fable` → `model: opus` in `agents/fable-advisor.md` and run the session on Opus. Same pattern, the Fable role shifts down to Opus.
- **Both implementation lanes** run codex at the `sandbox_mode` in your `~/.codex/config.toml`; since v5.5 the lanes pass no `--sandbox` flag, and `codex exec` is `read-only` when the key is unset, so set `sandbox_mode = "workspace-write"` there (the lanes' preflight reports `unavailable` until you do). If you work in a disposable VM and want the lanes unsandboxed, type `/fable-advisor:setup-dangerous-yolo-codex` yourself; nothing else in the plugin will run it for you. Both lanes need the [OpenAI Codex CLI](https://github.com/openai/codex) installed and authenticated (`npm i -g @openai/codex`, then `codex login`). `codex-implementer` invokes **GPT-5.6 Luna** (`gpt-5.6-luna`, always at `max`) and `sol-implementer` invokes **GPT-5.6 Sol** (`gpt-5.6-sol`, efforts low–ultra). GPT-5.6 access may be limited during preview; without model access, an installed/authenticated CLI, or successful authentication, a lane reports `STATUS: unavailable` — it never silently falls back to a Claude model. Without Codex at all, the pattern degrades to advisor-only mode (below).
- **The browser lane** (`astra-operator`) needs a Codex MCP server named `playwright_chrome`: headless Playwright Chrome, disabled at rest, enabled by the lane per run. The plugin does not create it; the **`playwright-mcp-setup` skill** does, on any platform, by running `scripts/setup-playwright-mcp.sh`. The script discovers `node`, npm's global root, `@playwright/mcp` (installing it when absent), and Playwright's Chromium, writes the block to `~/.codex/config.toml` with a backup, and proves the server answers an MCP handshake. It launches the server as `node .../cli.js`, never `npx`, because `npx.cmd` deadlocks on piped stdin on Windows. Ask for "set up playwright mcp" or run the script with `--check` to see what is missing.
- **Optional: the [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc)** (`/plugin marketplace add openai/codex-plugin-cc`, then `/plugin install codex@openai-codex`). When it's enabled, the orchestration skill uses `/codex:adversarial-review` as a GPT-family second reviewer ahead of the Fable review, `/codex:rescue` as a user-driven delegation path, and `/codex:setup` to diagnose a lane that reports `unavailable`. Not a dependency — the lanes drive `codex exec` directly either way.
- **Platforms:** Linux and macOS (macOS needs `brew install coreutils` for GNU `timeout`), and **Windows through Git Bash** — Claude Code's Bash tool on Windows already runs there, and Git Bash ships the coreutils the lane script needs. WSL also works, but it cannot see a Windows-side `codex` install. On Windows the lane script prints lane paths as `C:/...` so the Read tool and native tools accept them, kills native process trees through `taskkill`, and checks credential files by ACL instead of POSIX mode: lock a secret file down with `icacls <file> /inheritance:r /grant:r "%USERNAME%:F"` before naming it in a brief. The ACL check recognizes the English `NT AUTHORITY\SYSTEM` and `BUILTIN\Administrators` names only; on a localized Windows, remove those entries too and grant just your user.
- Heads-up: if a pinned Claude model isn't available on your account, Claude Code silently falls back to your session model — the pattern degrades quietly rather than erroring. If advisor verdicts feel unremarkable, check your plan. (This quiet fallback applies only to Claude model pins — the codex lanes always fail loudly with a structured error.)

Model resolution order in Claude Code: `CLAUDE_CODE_SUBAGENT_MODEL` env var → per-invocation `model` parameter → agent frontmatter → session model. Effort resolution: `CLAUDE_CODE_EFFORT_LEVEL` env var → agent frontmatter `effort` → session `/effort`. None of this plugin's agents set `effort`, so the advisor follows your session; the codex lanes take theirs from the spec.

## Use it

With the session on Fable, just ask for work — the orchestration skill routes it:

```
Add rate limiting to our public API. Design it, delegate the
implementation, and verify the evidence before you call it done.
```

The architect writes the spec, picks the lane and effort (rate limiting touches concurrency — a good case for `sol-implementer` at `max`, or for racing it against `codex-implementer` and picking the stronger diff), reads the diff and verification evidence when the report comes back, sends the finished work to `fable-advisor` for the final review, and only then reports done.

## Lane mechanics

All Codex-backed lanes share `scripts/lane.sh`: detached launch under a 3540 s cap, bounded wait, deadline kill, credential `splice-secret`, and `scrub`.
Run `bash tests/lane-smoke.sh` to exercise it with a dummy command in seconds; the Windows port was verified on Git Bash (Windows 11) and on Linux under WSL; macOS was not re-run for it.
Agents resolve it through `CLAUDE_PLUGIN_ROOT`, with a fallback to the plugin cache.
`scripts/setup-yolo-codex.sh` (behind the user-typed `/fable-advisor:setup-dangerous-yolo-codex` command) has its own smoke test, `bash tests/setup-yolo-codex-smoke.sh`, which runs against temporary config files only.

To make the doctrine always-on, add one line to your project's `CLAUDE.md`:

```
You are the architect — minimize your own token volume. Delegate all
implementation through the orchestration skill's routing table (never
type code yourself), name a reasoning effort per Sol task, delegate broad
codebase exploration to cheap read-only agents, verify evidence before
accepting any lane's report, and get a fable-advisor review before
reporting any deliverable done.
```

## Commitment boundaries and the final review

Even the architect gets a second opinion. The `fable-advisor` agent is a read-only skeptic on the same model as the architect but in a clean context — — consulted before architecture decisions, migrations, API designs, whenever a problem has resisted two attempts, and **always once at the end of a deliverable**, where it reads the accumulated diff with fresh eyes, against the stated goal rather than the conversation, and returns ship / fix-first / rethink. It never implements. It sees the code fresh, without your conversation's accumulated assumptions — that context-clean skepticism is what the final review buys. For an independent-model review on top, the Codex plugin's `/codex:adversarial-review` slots in just before it.

## Advisor-only mode (the original pattern)

The minimal arrangement, for when you'd rather skip the orchestration layer: run the session on Sonnet and consult `fable-advisor` only at commitment boundaries.

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

**Is this Anthropic's "advisor tool"?** No — that's a server-side API feature. These are plain Claude Code subagents plus a skill: readable, editable, no beta flags.

**Does this work on claude.ai?** No — subagent model routing is Claude Code only (CLI, desktop, VS Code, web).

**Why not just let Fable write the code too?** You can. It's excellent. It's also the most expensive model per token, and most of a session's tokens are implementation mechanics that the codex lanes handle at near-parity — and from a different vendor, which buys you a real second opinion. Spend the premium where it changes outcomes: the architecture and the final review.

**What's in v5.5 (this fork)?** The implementation lanes no longer pass `--sandbox workspace-write`; codex runs at the operator's own `sandbox_mode`, so the sandbox posture is set once per host in `~/.codex/config.toml` instead of being baked into the plugin, and the old `sandbox-fallback: allowed` spec line is gone. **Action required on upgrade:** `codex exec` is `read-only` when `sandbox_mode` is unset, so add `sandbox_mode = "workspace-write"` to your config to keep the previous behavior; the lanes' preflight reports `unavailable` with that instruction until you do. A new skill, `/fable-advisor:setup-dangerous-yolo-codex`, sets `sandbox_mode = "danger-full-access"` with a backup (`scripts/setup-yolo-codex.sh`, `--dry-run` and `--revert` supported). It is gated on the user typing that exact command: the architect, the lanes, memory, and other skills must never trigger it, because unsandboxed codex runs with your credentials and a VM snapshot does not undo a pushed commit or a spent API key.

**What's in v5.4 (this fork)?** The Luna lane is pinned at `max`. Effort on Luna is a token-count dial, not a price tier: the per-token rate is the same at every effort, and on the Artificial Analysis Intelligence Index (as repriced in July 2026 by the [GPT-5.6 model-selection guide](https://gist.github.com/lrehmann/ec36cc83f19bdf85b9f3ea19f02c9727)) Luna scores 33 / 38 / 46 / 49 / 51 at `low` / `medium` / `high` / `xhigh` / `max` for roughly $0.008 / $0.010 / $0.018 / $0.028 / $0.042 per task — the whole ladder costs about three cents, and at that repricing `max` buys about 86% of Sol `max`'s score for about 4% of its per-task cost ([Artificial Analysis](https://artificialanalysis.ai/articles/gpt-5-6-has-landed), at launch pricing before the 80% Luna price cut, put Luna `max` at 75 on the Coding Agent Index against Sol's 80, at about 80% lower cost per task). The lane runs detached under a 59-minute cap and the architect verifies every diff, so time to first token matters little and a shallow answer costs more (a corrected spec, a rerun, an escalation to Sol) than the extra reasoning tokens. The known downsides of `max` — about 136 s to first token, roughly double the output tokens of `high`, faster context consumption on very long runs ([PostTrainBench](https://arxiv.org/pdf/2603.08640) saw `medium` beat `high` on GPT-5.1 Codex-Max, a different model, for that reason) — are reduced, not removed, by keeping each Luna spec to one coherent change with one verification command, which the spec contract already requires. Sol and Astra keep per-task effort because their dollars are not small.

**What's in v5.2 (this fork)?** Two more agents: **`data-investigator`** (Claude Sonnet, read-only) runs the architect's queries and returns tables so raw data stays out of the Fable context, and **`astra-advisor`** (GPT-6 Astra via Codex, read-only sandbox) gives a cross-vendor second opinion on decisions, diffs, and findings. The orchestration skill gained a work-types routing table, a cost and duration section, a spec pre-check for existing files, guidance on second review passes and on treating advisor evidence requests as hypotheses, and harness notes.

**What's in v5.1 (this fork)?** A fourth lane: **`astra-operator`** runs GPT-6 Astra through Codex with an isolated headless Playwright Chrome MCP server for UI verification, screenshots, login flows, drag-and-drop, and browser E2E; the **`computer-use`** skill tells the architect when to route there and what counts as browser evidence. It needs a `playwright_chrome` entry in `~/.codex/config.toml` (headless, isolated, installed Chrome). The codex lanes also gained the hardening listed in the fork note above.

**Upgrading from v4?** v5 moves the session architect from Opus to **Fable 5.1**, replaces the Fable 5 `fable-implementer` lane with **`sol-implementer`** (GPT-5.6 Sol via Codex), and **unpins reasoning effort everywhere** — the architect names it per task in a new sixth spec line. The advisor is now Fable 5.1. The Codex plugin integration is new and optional. If you still want a Claude implementation lane, grab [`fable-implementer.md` from the v4.0 tree](https://github.com/DannyMac180/fable-advisor/blob/ad2bdc3/agents/fable-implementer.md).

**Upgrading from v3?** v4 moved the architect to Opus, removed the Grok 4.5 lane, and made `codex-implementer` the default typing lane; if you still want the Grok lane, grab [`grok-implementer.md` from the v3.1 tree](https://github.com/DannyMac180/fable-advisor/blob/b3b50a9/agents/grok-implementer.md).

**Why GPT lanes in a Claude plugin?** Vendor diversity. Models from one family share blind spots; an independent implementation from a different lineage catches what same-family review misses — and with Claude as the architect and reviewer, every diff gets cross-vendor review for free. The architect and reviewer stay Claude — the lanes are producers, not judges.
utm_source=github&utm_medium=readme&utm_campaign=fable-advisor) to get new posts to your inbox.

## License

MIT
