---
name: orchestration
description: Routing doctrine for the architect-as-orchestrator pattern — how a Fable 5.1 session delegates routine implementation to the GPT-5.6 Luna lane, escalates high-complexity one-offs to the GPT-5.6 Sol lane, sends read-only data pulls to the data-investigator lane, picks a reasoning effort per task, and gets every deliverable reviewed by the Fable advisor (and, on anything of moderate complexity or above, the Astra advisor) before reporting done. USE WHEN delegating implementation or investigation work, choosing between codex-implementer/sol-implementer/data-investigator lanes, choosing a reasoning effort for a lane, writing a spec for a subagent, deciding whether to consult fable-advisor or astra-advisor, using the Codex plugin's review skills, managing session cost or token spend, or running any multi-task build where the session is the architect.
---

# Orchestration — the architect's routing doctrine

The session is the architect: it owns requirements, architecture, decomposition, specs, routing, verification, and the written findings. It should almost never type implementation code, and it should almost never hold raw data in its context. Every implementation task gets routed to the cheapest lane and the lowest reasoning effort that is adequate for it — escalation to Sol, or to a higher effort, is deliberate, per task, never a fixed binding — every data pull goes to the investigation lane, and every finished deliverable gets a Fable review before the architect reports done.

## Cost discipline — the prime directive

The economics of this pattern: Fable 5.1 orchestrates (judgment-heavy, volume-light), GPT-5.6 Luna does the routine typing (volume-heavy, cheap, cross-vendor), GPT-5.6 Sol takes the hard one-offs (cross-vendor, expensive, only when judgment decides the outcome), Sonnet runs the queries and returns tables, and Fable 5.1 reviews in a clean context before anything ships. Three rules follow.

**Emit judgment, not volume.** The architect's output is decomposition, specs, routing decisions, verdicts on diffs, findings, and short reports. It does not type implementation code, test bodies, boilerplate, or config files. A code block longer than an interface signature or a few illustrative lines is a spec that hasn't been delegated yet — stop and delegate it. Fixing a lane's bug by hand is the same failure in disguise: send a corrected spec back to the lane instead. Findings and conclusions are the exception: the architect writes them, because deciding what is proven, what is hypothesis, and what to leave out is the judgment the premium buys. Lanes render and reformat what the architect wrote (tables from data files, an HTML site from the markdown, a changelog line, a PR body from the commit messages); they do not author the claims.

**Keep the context lean.** Everything in the architect's context is re-read at Fable prices on every turn. Delegate broad exploration, codebase searches, and log-grepping to a cheap read-only agent and keep only the conclusions; send database, log-platform, and API pulls to `data-investigator` and read its tables, not its files; read files yourself only when the decision genuinely depends on the exact code. Don't paste long files, full diffs, or verbose command output into the conversation when a path reference or an excerpt will do.

**Reason once, then hand off.** Do the hard thinking — the architecture, the interface design, the debugging hypothesis, the queries worth running — in one pass, capture it in the spec, and let the lane carry it from there. Re-deriving decisions across turns burns the premium twice.

What stays with the architect regardless of cost: decomposition, interface design, hypothesis selection when debugging, query design, spec writing, lane and effort routing, judging verification evidence and data, and writing the findings. Those tokens are what the premium is for — everything else is a candidate for delegation.

## Work types and lanes

| Work type | Producer | Invoke | Route here when |
|---|---|---|---|
| Routine implementation | GPT-5.6 Luna (effort per task) | `codex-implementer` agent | The spec fully determines the outcome: boilerplate, wiring, CRUD, mechanical edits, straightforward features. **Default implementation lane.** Requires the codex CLI. |
| High-complexity implementation | GPT-5.6 Sol (effort per task, up to `ultra`) | `sol-implementer` agent | The outcome depends heavily on judgment the spec can't capture: subtle concurrency, non-trivial algorithms, security-sensitive paths, hard debugging, wide-blast-radius refactors — or the routine lane has already failed the task twice. One-off escalations, never the default. Requires the codex CLI. |
| Investigation / data pulls | Claude Sonnet (session effort) | `data-investigator` agent | Read-only queries the architect has written or bounded: SQL against a replica, log-platform (APL) queries, API listings, file scans. The lane runs them, writes raw output to files, and returns compact tables and one-line observations; the architect judges. Never for conclusions, never for mutations. |
| Codebase exploration | Claude (cheap tier) | `Explore` or equivalent read-only agent | Broad "where is X / how does Y work" searches whose answer is a short list of file:line facts. Keep only the conclusions. |
| Documents | Architect writes; lanes render | `codex-implementer` for rendering | Findings, conclusions, and claims are the architect's. Rendering them (tables from TSV, static HTML site, changelog line, PR body from commits, artifact prompt) is routine and delegable. |
| Review, same family | Fable 5.1 (inherits session effort) | `fable-advisor` agent | Commitment boundaries and the mandatory end-of-deliverable review — see below. Not an implementation lane. |
| Review, cross-vendor | GPT-6 Astra (effort per consult) | `astra-advisor` agent | Automatic on any deliverable of moderate complexity or above (triggers listed under the reviews), once the Fable review is adjudicated; also on request. Read-only via codex. Requires the codex CLI. |
| Browser / computer use | GPT-6 Astra (effort `medium` by default) | `astra-operator` agent | Anything that needs a real browser or desktop: UI verification, screenshots, login flows, drag-and-drop, browser E2E. Doctrine lives in the `computer-use` skill. |

Deciding rule for implementation: how much does the outcome depend on judgment the spec can't capture? Little → the default Luna lane; you will verify anyway. A lot, and mistakes are costly → escalate to `sol-implementer`, or keep that piece with the architect. A routine-lane task that fails its spec once gets a corrected spec; twice, it escalates to Sol — repetition is evidence the task was misclassified. A `contested` report is not a failure and does not count toward that: the lane stopped because the spec was wrong, and sending the same wrong spec to a more expensive model buys nothing. A contest you refuted with evidence and the lane still could not act on is a lane failure and does count.

Deciding rule for investigation: if the next step is "run these queries and tell me the numbers", it goes to `data-investigator`. If the next step is "decide what to query", it stays with the architect. Access setup (tunnels, credential resolution, runner scripts) is architect work done once; the lane reuses the runners.

Both implementation lanes are the cross-vendor half of the pattern: their output comes from a non-Anthropic family, so the Claude architect's verification and the Fable review are genuine cross-vendor checks, not same-family self-review. The investigation lane and the exploration agents are same-family by design; they execute, they do not judge.

If a codex lane returns `unavailable`, `timeout`, or `execution-error`, say so explicitly in your report and decide: re-route to the other codex lane (Luna ↔ Sol), or keep the piece with the architect. An `unavailable` whose REASON is a CLI/helper version mismatch or a sandbox write denial is a host problem, not a lane problem; re-routing Luna ↔ Sol will fail identically, so fix the host (`/codex:setup`) or, for the sandbox case only, resend the same spec with the line `sandbox-fallback: allowed` if the operator accepts codex running under their own configured sandbox mode. Never quietly absorb the substitution or the cost change. All codex lanes fail loudly on a missing or unauthenticated codex CLI — there is no Claude fallback inside a lane by design.

## Choosing the reasoning effort

Nothing in the lanes pins an effort — the architect names one per task in the spec, and the lane passes it through unchanged. Pick the lowest rung that is adequate; effort is cost and wall-clock, not a quality dial to leave at max.

| Rung | Luna | Sol | Astra advisor | Use for |
|---|---|---|---|---|
| `low` / `medium` | ✓ | ✓ | ✓ | Mechanical edits, renames, wiring, boilerplate, config, tests that mirror an existing pattern |
| `high` | ✓ | ✓ | ✓ (default) | Ordinary features with a couple of design decisions left to the lane; most routine work with real logic in it; ordinary consults |
| `xhigh` | ✓ | ✓ | ✓ | Tricky logic, multi-file changes with interactions, the second attempt after a spec correction |
| `max` | ✓ | ✓ | ✓ | The hardest single-lane tasks: concurrency, security-sensitive paths, gnarly debugging; consults on findings that will be challenged |
| `ultra` | — | ✓ | — | Sol only. Maximum reasoning plus codex's own internal task delegation — slow; reserve for wide-blast-radius refactors and problems that have resisted two attempts |

Luna has no `ultra` and the lane will refuse rather than round it; a task that seems to need `ultra` is a task for Sol. If you omit the effort, the lane runs codex at the user's own configured default and flags that in `GAPS` — acceptable for trivial work, never for an escalation. `data-investigator`, the exploration agents, and `fable-advisor` are Claude agents and inherit the session effort; a `REASONING` line sent to them is ignored.

The architect's own effort and the Fable advisor's come from the session (`/effort`), since Claude Code sets subagent effort per agent definition, not per call. Raise the session effort before an architecture decision or a final review that deserves it; drop it back for routine turns.

## Cost and duration expectations

Plan the split before the first dispatch, not after the first timeout.

- Every codex lane launches its run detached under a 3540 s cap (59 minutes) and polls it in bounded foreground calls, because the Bash tool ceiling is 600 s per call and an interrupted run is the worst outcome: the edits land, codex's own verification and final message are lost, and the architect re-verifies from scratch. The mechanics live in the plugin's `scripts/lane.sh` and are covered by `tests/lane-smoke.sh`. Luna at `high` on a well-specified change touching a handful of files typically lands in 5 to 15 minutes including its own verification run; a spec touching a dozen files plus tests and docs has taken more than 10, and Luna at `max` and Sol at `xhigh` and above routinely need 15 to 30. Do not shorten the cap to save wall clock. A lane report of `timeout` with a finished diff is possible when the host has no GNU timeout, when something hung, or when a genuinely slow verification step outran the cap; treat the diff as untrusted, run the verification yourself, and then decide between keep and resend.
- Split specs so each lane call owns one package or one coherent change with one verification command. A spec whose verification runs a whole monorepo's tests will time out on the verification, not the change; scope the verification to the package and rerun the wider suite yourself.
- A lane report costs the architect a few hundred tokens to read; a lane's raw diff can cost thousands. Read the diff once, judge, and do not re-read it on later turns.
- An `Explore` sweep of a service returns in 3 to 8 minutes and replaces dozens of architect-side file reads. A `data-investigator` run is bounded by the slowest query; put a statement timeout in the runner so a bad query fails in minutes, not the whole lane.
- A `fable-advisor` consult costs cents and returns in under a minute for a diff of a few hundred lines. A second pass on the same advisor (see below) costs less than the first because its context is retained.
- An `astra-advisor` consult is a full codex run: budget the same 5 to 15 minutes as a Luna task, more for a diff of several hundred lines.

## The spec contract

Implementers share none of your conversation context. Every delegation prompt carries all six parts:

1. **Objective** — what to build or change, one paragraph
2. **Files** — exact paths to create or modify, and the working directory when it is not the session cwd (the lane `cd`s there before launching codex). Before writing this part, list what already exists at those paths and next to them, including test files beside the sources (`ls`, a glob, or the exploration agent). "Add" a file that exists and the lane will either clobber it or quietly merge; say "modify" and name what must survive. When other lanes or the architect have uncommitted work in the same tree, add one line, `Other work in flight: <paths>`, so the lane lists those paths uninspected instead of reporting them as unauthorized.
3. **Interfaces** — signatures, types, or API shapes the code must match
4. **Constraints** — project conventions, things not to touch
5. **Verification** — the command(s) that prove it works, scoped to what the change can affect, plus, for every file the spec touches, at least one command that actually parses or compiles it. Test targets routinely build a subset (a test build that skips namespaces, one Go package, one crate, one jest project, one tsc project reference); when the test command's build does not include a touched file, name the command that does (the package's full compile, a typecheck of the owning project, `go build ./...`, `cargo check`, a byte-compile or lint pass) so a syntax error in an untested file cannot pass. The lane reports which check covered which file
6. **Reasoning** — one line, `REASONING: <effort>`, chosen from the table above

A spec you can't finish writing is a signal the decision isn't made yet — that's architect work, not a reason to hand the ambiguity to a cheaper model.

The investigation spec is the five-part variant the `data-investigator` agent documents: objective, data sources and runners, queries, output files, observations wanted. No `REASONING` line. Write the queries yourself; the lane runs them as given.

## Parallelism

Independent specs (no shared files, no ordering dependency) launch as parallel agents in a single message. Sequential chains and single-file surgery stay serial. Investigation runs and exploration sweeps are independent of implementation and can run alongside it. For high-stakes work, run `codex-implementer` and `sol-implementer` on the same spec and let the architect pick the stronger diff — two capability tiers, one judged result.

Parallel lanes share one working tree, so each sees the others' uncommitted files. Put the `Other work in flight` line in each spec and expect each lane to report only its own diff, with the rest listed on its `OTHER WORK` line. A lane report that calls another lane's files, or the architect's, unauthorized is noise, not a finding; do not act on it.

## Commitment boundaries and the reviews

Consult `fable-advisor` (read-only, verdict in under 300 words) at the moments that decide whether the next hour is wasted:

- Before committing to an architecture, data migration, API shape, or refactor strategy
- Whenever the same problem has resisted two distinct attempts
- **Always, once, at the end of a deliverable** — the advisor reads the accumulated changes (or the findings document) with fresh eyes, against the stated goal rather than the conversation, and returns ship / fix-first / rethink. The architect does not report done before this review.

Pass it the decision (or, for final review, the diff or report and the stated goal), the constraints, and the options considered. Act on the verdict or surface the disagreement — never silently ignore it.

**A second pass is normal.** The common shape is fix-first, patch, re-review. Send the follow-up to the same advisor with `SendMessage` (its context is retained, so it re-reads only the changed sections) rather than spawning a fresh consult. Stop when it says ship or when the remaining items are ones you have decided to accept and have said so.

**Advisor requests are hypotheses, not orders.** When the advisor asks for more evidence ("count X in the logs", "rerun with Y"), check feasibility against what the sources can actually express before spending a lane on it, exactly as you would check a lane's report before believing it. An advisor can be confidently wrong about what a data source records. Report back what was infeasible and why.

One honest caveat: `fable-advisor` and the architect are the same model. The final review is still worth it — it reads the diff in a clean context, against the goal rather than the conversation, without the assumptions the architect accumulated while writing the specs — but it is a fresh-eyes check, not an independent-model check. Cross-vendor independence comes from the codex lanes producing the code, from `astra-advisor` on every deliverable that qualifies (below), and, when the Codex plugin is installed, from its review skills (below). Use `astra-advisor` in addition to, not instead of, the Fable review, and use it by default rather than by exception. When the two advisors disagree, the architect decides and says which verdict it took and why.

**The Astra review is automatic at moderate complexity and above.** Once the Fable review is adjudicated — it said ship, or the remaining items are ones you have accepted and said so — run `astra-advisor` on the same diff or document. Run it by default; skip it only when every one of these holds: the change is one or two source files (tests and docs that accompany them do not count), it went through the Luna lane only at `low` or `medium`, the Fable review passed it on first look, and it did not touch architecture, a public API, a CLI, a data shape, a migration, a security-sensitive path, or concurrency. Run it regardless of size whenever the work went to `sol-implementer`, changed any of those things, is a findings document whose claims outsiders will challenge, is a problem that resisted two attempts, or the user asked. Breadth alone is not complexity: a contested-spec resend, an exploration agent alongside one lane, or a code change with its tests and docs in tow does not by itself make a deliverable moderate. Pick the review effort independently of the task: `high` by default, `max` when the task ran Sol at `max` or `ultra` (Astra has no `ultra`). If `/codex:adversarial-review` already ran on the final diff, it satisfies this requirement; do not run both. Treat Astra's findings the way you treat the Fable advisor's: hypotheses to check against the tree, then fix or accept and say so. A patch after an Astra fix-first goes back to `fable-advisor` by `SendMessage`, which is cheap; an Astra re-review is another full codex run at the same cost as the first, so batch the fixes before asking for one. The architect does not report done with an Astra review pending.

## The Codex plugin (optional)

If the official OpenAI Codex plugin for Claude Code is installed (`codex@openai-codex` under `enabledPlugins` in the user's Claude Code settings; `/plugin list` shows it), its commands become available in the session. It talks to the local `codex` binary over its app-server protocol, so it shares the same install and login as the lanes. The doctrine uses it three ways:

- **`/codex:adversarial-review`** — run it on the accumulated diff *before* the `fable-advisor` final review on any deliverable that touched a security-sensitive path, a migration, or an API shape. It is a GPT-family reviewer and so an independent-model check on the Claude reviewer's blind spots; `astra-advisor` is the same idea with a chosen model and effort and works without the plugin; either one on the final diff satisfies the automatic cross-vendor review, never run both. Feed its findings into the advisor consult as context. `/codex:review` is the lighter pass for deliverables below the automatic threshold when the user wants one anyway.
- **`/codex:rescue --model <slug> --effort <rung>`** — a write-capable delegation the user can drive directly, with `/codex:status`, `/codex:result`, and `/codex:cancel` for background jobs. Use it when the user asks for it, or for a long-running investigation you want off the session's critical path. It caps effort at `xhigh` and returns Codex's output rather than the lane report, so the architect still reads the diff and re-runs verification itself. For `max`/`ultra`, or whenever you want the structured report and the empty-diff check, use the lanes.
- **`/codex:setup`** — point the user here when a lane reports `unavailable`; it verifies the binary, version, and login.

The plugin's optional stop-time review gate (`/codex:setup --enable-review-gate`) runs a Codex review every time the session stops; it overlaps with the mandatory advisor review and can loop, so leave it off under this pattern unless the user chooses otherwise. Without the plugin the pattern is unchanged — it adds a reviewer and a manual delegation path, it is not a dependency.

## Verification

Reports are claims, not evidence. Before accepting any lane's work: read the diff, and re-run the verification command (or spot-check its quoted output against the working tree). "Should work", "tests should pass", or a report with no command output means the task is not done. An empty diff with a clean exit is a refusal, not a success — the lanes report it as `refused`; treat it as one. A lane that reports a spec gap gets a corrected spec, not a "use your judgment".

**Lane objections are hypotheses, not orders.** A `STATUS: contested` report means the lane read the spec against the tree and found defects it lists in `OBJECTIONS`; it did no work. Check each objection against the tree before acting — the routine lane runs a weaker model than the architect and will sometimes contest a spec that is fine — then either correct the spec or answer the objection with the evidence that refutes it, and resend to the same lane with `SendMessage` so it keeps the context of the first pass. Never answer a contest with "use your judgment", never rewrite the spec to whatever the lane guessed you meant, and never do the work yourself because the lane pushed back. A spec contested on three corrected versions is a decision the architect has not actually made — take it to `fable-advisor` before writing a fourth version.

A lane's verification covers only what its commands parsed. Before accepting, check that every touched file went through a compile, typecheck, or lint the lane actually ran; when the test build skips a file, run the covering check yourself. Observed 2026-09-15: a ClojureScript test build that never compiled the portal namespaces passed with an unbalanced paren in one of them; the linter caught it.

The same rule applies to investigation output: a table in a `data-investigator` report is computed from a file the lane wrote; spot-check one number against that file before it goes into a finding.

The lane's `DIAGNOSTICS:` and `SANDBOX:` lines are for the human; surface them verbatim in your report.

## Harness notes

Things about the Claude Code harness that cost time when learned mid-task:

- **Waiting.** Chained `sleep` in a Bash call is blocked. To wait on CI, run `gh run watch <id> --exit-status` in a background Bash call and read its output when notified, or use an `until <check>; do sleep 20; done` loop in one background call. Poll one exact run id, not `gh run list` in a loop.
- **Working directory drift.** The session cwd can change after a `cd` inside a command, and the harness reports it as an environment update. Use absolute paths in every command that matters, and re-`cd` at the start of scripts.
- **No artifact tool.** The session cannot create shareable claude.ai artifacts. Shareable output means files in the repository or a temp directory, a static HTML site the user hosts, or a markdown file with a rendering prompt at the top that the user pastes into claude.ai.
- **Background agents notify once.** A backgrounded agent's result, and a lane's reply to a `SendMessage` resume, arrive as task notifications; there is no blocking wait. Do not poll, and do not predict the result before the notification arrives. Never call `TaskOutput` on an agent task: its output file is the agent's whole JSONL transcript and it lands in your context (observed 2026-09-15). If you want a timer while a lane works, run `sleep N` in a background Bash call and let its completion wake you, or do other work.
- **Subagents cannot receive notifications.** A lane that backgrounds codex and ends its turn will never be woken; the lanes launch codex detached through `scripts/lane.sh` and poll it in bounded foreground calls for that reason.
- **Temp data.** Keep investigation output under an ignored directory in the repository (`tmp/<investigation>/`) so it survives the session, stays out of git, and can be handed to a rendering lane later.
