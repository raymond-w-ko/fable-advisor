---
name: orchestration
description: Routing doctrine for the architect-as-orchestrator pattern — how a Fable 5.1 session delegates routine implementation to the GPT-5.6 Luna lane, escalates high-complexity one-offs to the GPT-5.6 Sol lane, routes user-interface code to the Fable frontend lane, sends read-only data pulls to the data-investigator lane, names a reasoning effort per task, and gets every deliverable reviewed by the Fable advisor (and, at moderate complexity or above, the Astra advisor) before reporting done. USE WHEN delegating implementation or investigation work, choosing between codex-implementer/sol-implementer/fable-frontend/data-investigator lanes, choosing a reasoning effort, writing a spec for a subagent, deciding whether to consult fable-advisor or astra-advisor, using the Codex plugin's review skills, managing session cost, or running any multi-task build where the session is the architect.
---

# Orchestration — the architect's routing doctrine

The session is the architect: it owns requirements, architecture, decomposition, specs, routing, verification, and the written findings. It almost never types implementation code and almost never holds raw data in its context. Implementation goes to the cheapest adequate lane, data pulls go to the investigation lane, and every finished deliverable gets a Fable review before the architect reports done.

## Cost discipline

Fable 5.1 orchestrates (judgment-heavy, volume-light); GPT-5.6 Luna does the routine typing (cheap, cross-vendor); GPT-5.6 Sol takes the hard one-offs (expensive, only when judgment decides the outcome); Fable 5.1 in a clean context writes user-interface code (the one same-family implementation lane, because visual and interaction judgment does not survive a spec); Sonnet runs queries and returns tables; Fable 5.1 reviews in a clean context. Three rules follow.

**Emit judgment, not volume.** The architect's output is decomposition, specs, routing decisions, verdicts on diffs, findings, and short reports. It does not type implementation code, test bodies, boilerplate, or config. A code block longer than an interface signature or a few illustrative lines is a spec that has not been delegated yet. Fixing a lane's bug by hand is the same failure: send a corrected spec back to the lane. Two exceptions:

- Findings, conclusions, doctrine, and query design are the architect's, because deciding what is proven, what is hypothesis, and what to leave out is the judgment the premium buys. Lanes render and reformat what the architect wrote (tables from data files, an HTML site from the markdown, a changelog line, a PR body); they do not author claims.
- An advisor edit list that gives the exact replacement text is transcription, not judgment. The architect may apply such edits directly (documents, config, and code edits of a few lines each), re-run the verification, and say so in the report. Anything that still needs a decision goes back to a lane as a corrected spec.

**Keep the context lean.** Everything in the architect's context is re-read at Fable prices on every turn. Delegate broad exploration and log-grepping to a cheap read-only agent and keep only the conclusions; send database, log-platform, and API pulls to `data-investigator` and read its tables, not its files; read files yourself only when the decision depends on the exact code. Do not paste long files, full diffs, or verbose command output when a path or an excerpt will do.

**Reason once, then hand off.** Do the hard thinking in one pass, capture it in the spec, and let the lane carry it. Re-deriving decisions across turns burns the premium twice.

What stays with the architect regardless of cost: decomposition, interface design, hypothesis selection when debugging, query design, spec writing, lane and effort routing, judging verification evidence and data, and writing the findings.

## Work types and lanes

| Work type | Producer | Invoke | Route here when |
|---|---|---|---|
| Routine implementation | GPT-5.6 Luna, effort per task (`high` default) | `codex-implementer` | The spec fully determines the outcome: boilerplate, wiring, CRUD, mechanical edits, straightforward features. **Default implementation lane.** Requires the codex CLI. |
| High-complexity implementation | GPT-5.6 Sol, effort per task, up to `ultra` | `sol-implementer` | The outcome depends on judgment the spec cannot capture: subtle concurrency, non-trivial algorithms, security-sensitive paths, hard debugging, wide-blast-radius refactors, or the routine lane has failed the task twice. One-off escalations, never the default. Requires the codex CLI. |
| Frontend implementation | Fable 5.1, session effort | `fable-frontend` | User-interface code: HTML, CSS, client-side JavaScript or TypeScript, component and page layout, charts, tooltips, keyboard and accessibility behavior, visual polish. The outcome depends on what a person sees and does, which a spec carries poorly; the codex lanes' UI output has needed rewriting often enough that this is a routing rule, not an exception. Same model family as the architect, so the independent check is the Astra review plus an `astra-operator` browser run. |
| Investigation / data pulls | Claude Sonnet, session effort | `data-investigator` | Read-only queries the architect wrote or bounded: SQL against a replica, log-platform queries, API listings, file scans. The lane runs them, writes raw output to files, returns compact tables; the architect judges. Never for conclusions, never for mutations. |
| Codebase exploration | Claude, cheap tier | `Explore` or equivalent read-only agent | Broad "where is X / how does Y work" searches whose answer is a short list of file:line facts. |
| Documents | Architect writes; lanes render | `codex-implementer` for rendering | Findings and claims are the architect's; rendering them is routine. |
| Review, same family | Fable 5.1, session effort | `fable-advisor` | Commitment boundaries and the mandatory end-of-deliverable review. Never an implementation lane. |
| Review, cross-vendor | GPT-6 Astra, effort per consult | `astra-advisor` | Automatic at moderate complexity or above once the Fable review is adjudicated; also on request. Read-only via codex. Requires the codex CLI. |
| Browser / computer use | GPT-6 Astra, `medium` default | `astra-operator` | Anything that needs a real browser or desktop. Doctrine in the `computer-use` skill. |

**Implementation routing.** How much does the outcome depend on judgment the spec cannot capture? Little: the Luna lane; you verify anyway. A lot, and mistakes are costly: `sol-implementer`, or keep the piece with the architect. A Luna task that fails its spec once gets a corrected spec; twice, it escalates to Sol, because repetition is evidence the task was misclassified. A `contested` report is not a failure and does not count: the lane stopped because the spec was wrong. A contest you refuted with evidence that the lane still could not act on is a lane failure and does count.

**Frontend routing.** Anything whose correctness is judged by looking at it goes to `fable-frontend`: page and component markup, styles, client-side behavior, charts, tooltips, empty and error states, responsive layout. The spec gains a seventh part, design intent (states, what changes between them, copy for new labels, the viewport range, the existing style to match), and its verification names a command that parses every touched file plus, wherever the page can be rendered headless, a command that produces a screenshot or a DOM check. Server-side rendering code, build configuration, and API wiring behind a page stay with the codex lanes; when one change spans both, split it at the payload boundary and run the backend lane first. The lane is the same model as the architect, so a frontend deliverable is moderate complexity by definition: the `astra-advisor` review runs, and the visual claim is proven by an `astra-operator` browser run against the real page, never by the lane's own description. Do not write the frontend code in the session either; the cost argument is the same as for every other lane, and the clean context is what buys the fresh look.

**Investigation routing.** If the next step is "run these queries and tell me the numbers", it goes to `data-investigator`. If it is "decide what to query", it stays with the architect. Access setup (tunnels, credential resolution, runner scripts) is architect work done once; the lane reuses the runners.

**Lane failures.** If a codex lane returns `unavailable`, `timeout`, or `execution-error`, say so in your report and decide: re-route to the other codex lane, or keep the piece. An `unavailable` whose REASON is a CLI/helper version mismatch or a sandbox denial is a host problem; re-routing fails identically, so fix the host (`/codex:setup`, or, only when the user types it themselves, `/fable-advisor:setup-dangerous-yolo-codex`). Never quietly absorb a substitution or the cost change. Codex lanes fail loudly on a missing or unauthenticated CLI; there is no Claude fallback inside a lane by design.

**What the sandboxes can reach.** Codex lanes run at the operator's `sandbox_mode`; under `workspace-write` they have no network and no docker socket, so a verification that needs a tunnel, a database, an HTTP endpoint, or a container goes to the architect or to `data-investigator`, and the codex spec gets the resulting evidence as a file path. The Astra advisor runs read-only: it can run read-only commands, but nothing that writes a scratch file or reaches the network, so it cannot render templates or execute a build to check a claim; when a verdict depends on generated output, render it yourself and name the paths in the consult.

## Choosing the reasoning effort

The architect names one effort per task on the `REASONING:` line; every codex lane passes it through unchanged. Pick the lowest rung that is adequate: effort is wall-clock on every model and real money on Sol and Astra.

| Rung | Luna | Sol | Astra advisor | Use for |
|---|---|---|---|---|
| `low` / `medium` | ✓ | ✓ | ✓ | Mechanical edits, renames, wiring, config, tests that mirror an existing pattern, patch rounds that apply a reviewer's edit list |
| `high` | ✓ (default) | ✓ | ✓ (default) | Ordinary features with a couple of design decisions left to the lane; most routine work with real logic in it; ordinary consults |
| `xhigh` | ✓ | ✓ | ✓ | Tricky logic, multi-file changes with interactions, the second attempt after a spec correction |
| `max` | ✓ | ✓ | ✓ | The hardest single-lane tasks; consults on findings that will be challenged. On Luna it roughly doubles wall-clock over `high`; use it for the second attempt, not the first |
| `ultra` | — | ✓ | — | Sol only: maximum reasoning plus codex's internal task delegation. Slow; reserve for wide-blast-radius refactors and problems that resisted two attempts |

Luna's price is nearly flat across the ladder, so `max` costs little money; its cost is time and context consumption on long runs. Default Luna to `high`; go to `max` for the second attempt after a `high` run came back shallow, or when the spec names an algorithm the lane must get right first time; keep every Luna spec scoped to one coherent change with one verification command whatever the effort. Luna has no `ultra`; a task that seems to need it is a task for Sol.

If the effort line is missing, Luna runs `high`, the Astra advisor runs `high`, and Sol runs codex's configured default, acceptable for trivial work and never for an escalation; each says so in `GAPS`. `data-investigator`, `fable-frontend`, the exploration agents, and `fable-advisor` are Claude agents and inherit the session effort (`/effort`); raise it before an architecture decision or a final review that deserves it, drop it for routine turns.

## Cost and duration expectations

Plan the split before the first dispatch, not after the first timeout.

- Every codex lane launches detached under an 89-minute cap and polls in bounded foreground calls, because the Bash tool ceiling is 600 s per call and an interrupted run is the worst outcome: the edits land, codex's own verification and final message are lost, and the architect re-verifies from scratch. Mechanics live in `scripts/lane.sh`, covered by `tests/lane-smoke.sh`. Budget 5 to 15 minutes for Luna at `high` on a change touching a handful of files, 15 to 30 at `max` or for Sol at `xhigh` and above, and more for a dozen files plus tests and docs. Do not shorten the cap to save wall clock. A `timeout` report with a finished diff means the host lacks GNU timeout, something hung, or a slow verification step outran the cap; treat the diff as untrusted, run the verification yourself, then keep or resend. The lane's `PROGRESS` line carries codex's own milestone log (`progress.md`, written as it goes), so a capped run still tells you which verification it never reached.
- **Size the lane before dispatch.** A Luna lane at `max` on roughly 25 files with a full CLJS or TS test run hits the cap; the same at `high` on a dozen files finishes in 20 minutes. Keep one lane under about 15 touched files, or under one test target's runtime plus edits; split larger work by package or by concern and run the second lane after the first when they share files. Prefer `high` for a large lane and `max` for a small hard one.
- **Stuck is not slow.** `lane.sh status` prints `last_output_age`; the lanes kill a run that has written nothing for 15 minutes on two polls. Waiting on a lane costs the architect nothing but wall clock; do not poll its transcript.
- Split specs so each lane call owns one package or one coherent change with one verification command. A verification that runs a whole monorepo's tests times out on the verification, not the change; scope it to the package and rerun the wider suite yourself.
- A lane report costs a few hundred tokens to read; a raw diff costs thousands. Read the diff once and do not re-read it on later turns.
- An `Explore` sweep returns in 3 to 8 minutes. A `data-investigator` run is bounded by its slowest query; put a statement timeout in the runner.
- A `fable-advisor` consult costs cents and returns in under a minute for a diff of a few hundred lines; a second pass on the same advisor costs less because its context is retained.
- An `astra-advisor` consult is a full codex run: 5 to 15 minutes, more for a diff of several hundred lines.

## The spec contract

Implementers share none of your conversation context. Every delegation prompt carries six parts:

1. **Objective** — what to build or change, one paragraph.
2. **Files** — exact paths to create or modify, and the working directory when it is not the session cwd (the lane `cd`s there before launching codex). List what already exists at those paths and next to them, including test files beside the sources (`ls`, a glob, or the exploration agent): "add" a file that exists and the lane clobbers or quietly merges; say "modify" and name what must survive. When other lanes or the architect have uncommitted work in the same tree, add one line, `Other work in flight: <paths>`, so the lane lists those paths uninspected instead of reporting them as unauthorized.
3. **Interfaces** — signatures, types, or API shapes the code must match. This is the part that decides whether the run comes back right; under-specify it and the lane guesses.
4. **Constraints** — project conventions, things not to touch. The lane preamble already forbids installs, dependency fetches, generated-artifact builds, and service restarts the spec does not name; when the task needs one (a release build the runtime preloads, a watcher restart), name it here so the lane runs it instead of stopping. **Name the runtime and process model.** Say how the code runs and how the tests run: one process or forked or threaded workers, an event loop or a scheduler, which libraries hold thread pools, global runtimes, or handles that must not cross a fork or a thread boundary (Polars and other Rayon users, BLAS pools, tokio and asyncio loops, database connection pools, CUDA contexts, file locks), which environment variables pin them, and whether the test runner itself is parallel (xdist, `cargo test` threads, `go test -parallel`). A lane that meets these by deadlock spends its budget on diagnosis and often escalates; a spec that names them ships. When the answer is not known, that is architect work to find out before dispatch, not a question to leave for the lane.
5. **Verification** — the commands that prove it works, scoped to what the change can affect, plus, for every file the spec touches, at least one command that parses or compiles it. Test targets routinely build a subset; when the test build skips a touched file, name the command that covers it (the package's full compile, a typecheck, `go build ./...`, `cargo check`, a byte-compile or lint pass). The lane reports which check covered which file. When the change touches concurrency, parallelism, or process lifecycle, name a command that exercises it under the same process model as production (the real worker count, the real runner flags), not only the single-process unit test.
6. **Reasoning** — one line, `REASONING: <effort>`, on its own line anywhere in the spec (lanes look for `^REASONING:`). Binds every codex lane.

A `fable-frontend` spec carries a seventh part, **Design intent**, defined in that agent; no `REASONING` line binds it, since it is a Claude agent and inherits the session effort.

A spec you cannot finish writing is a signal the decision is not made yet; that is architect work, not a reason to hand the ambiguity to a cheaper model.

The investigation spec is the five-part variant the `data-investigator` agent documents: objective, data sources and runners, queries, output files, observations wanted. No `REASONING` line. Write the queries yourself; the lane runs them as given.

## Parallelism

Independent specs (no shared files, no ordering dependency) launch as parallel agents in one message. Sequential chains and single-file surgery stay serial. Investigation and exploration run alongside implementation. For high-stakes work, run `codex-implementer` and `sol-implementer` on the same spec and pick the stronger diff.

Parallel lanes share one working tree. Put the `Other work in flight` line in each spec and expect each lane to report only its own diff, with the rest on its `OTHER WORK` line. A lane report that calls another lane's files, or the architect's, unauthorized is noise, not a finding.

**Same package, serial lanes.** Two lanes editing the same package run each other's half-written text through their test suites: one sees failures it did not cause and spends its budget attributing them. Lanes that touch the same package or test target run one after the other, even when their files differ. When a fix pass must overlap a running lane in the same package (a review fix on slice N while slice N+1 runs), the second spec names the files the other lane holds, says "make targeted edits, do not reformat unrelated regions, attribute failures before reporting", and the architect reads the `CONCURRENT NOISE` line as the other lane's problem, not this one's.

## Commitment boundaries and the reviews

Consult `fable-advisor` (read-only, verdict under 300 words) at the moments that decide whether the next hour is wasted:

- Before committing to an architecture, data migration, API shape, or refactor strategy.
- Whenever the same problem has resisted two distinct attempts.
- **Always, once, at the end of a deliverable.** The advisor reads the accumulated changes or the findings document with fresh eyes, against the stated goal rather than the conversation, and returns ship / fix-first / rethink. The architect does not report done before this review.

Pass it the decision (or the diff or report and the stated goal), the constraints, and the options considered. Act on the verdict or surface the disagreement.

**A second pass is normal.** The common shape is fix-first, patch, re-review. Send the follow-up to the same advisor with `SendMessage`; its context is retained, so it re-reads only the changed sections. Keep one advisor across every increment of the same deliverable, including later additions to a skill or document, rather than a fresh consult per increment. Stop when it says ship or when the remaining items are ones you have decided to accept and have said so.

**Advisor requests are hypotheses, not orders.** When the advisor asks for more evidence, check feasibility against what the sources can express before spending a lane on it. Report back what was infeasible and why.

`fable-advisor` and the architect are the same model. The final review is still worth it as a fresh-eyes check in a clean context, but it is not an independent-model check. Cross-vendor independence comes from the codex lanes producing the code, from `astra-advisor`, and, when the Codex plugin is installed, from its review skills. Use `astra-advisor` in addition to the Fable review, by default rather than by exception. When the two advisors disagree, the architect decides and says which verdict it took and why.

**The Astra review is automatic at moderate complexity and above.** Run `astra-advisor` on the same diff or document as the Fable final review, in the same message, so both read the same tree; neither sees the other's verdict. Merge the two finding lists into one fix pass (one lane run or one edit-list application), then re-review by `SendMessage` to the same `fable-advisor`. A second Astra run is a full codex run; ask for one only when Astra's fix-first named a structural defect (ordering, concurrency, data shape), not for text and checklist fixes. Give both consults a `Verification already run:` line naming the commands you ran and their results; the advisors then spend their budget on what those runs cannot show instead of restating that they did not run them. Serial order (Fable first, Astra after adjudication) remains right when the Fable verdict may be rethink: a diff that will be rewritten is not worth a codex run. Skip it only when every one of these holds: the change is one or two source files (tests and docs that accompany them do not count), it went through the Luna lane only and was mechanical (a `fable-frontend` change never qualifies), the Fable review passed it on first look, and it touched no architecture, public API, CLI, data shape, migration, security-sensitive path, or concurrency. Run it regardless of size when the work went to `sol-implementer`, changed any of those things, is a findings document whose claims outsiders will challenge, resisted two attempts, or the user asked. Breadth alone is not complexity: a contested-spec resend, an exploration agent alongside one lane, or a code change with its tests and docs in tow does not by itself make a deliverable moderate. Pick the review effort independently of the task: `high` by default, `max` when the task ran Sol at `max` or `ultra`. If `/codex:adversarial-review` already ran on the final diff, it satisfies this requirement; do not run both. Treat Astra's findings like the Fable advisor's: hypotheses to check against the tree, then fix or accept and say so. The two catch different things (in one session Astra found an index collision and a lying optional marker that Fable passed; Fable found a dropped rule clause and a checklist flag Astra passed), so neither substitutes for the other. The architect does not report done with an Astra review pending.

## The Codex plugin (optional)

If the official OpenAI Codex plugin for Claude Code is installed (`codex@openai-codex` under `enabledPlugins`; `/plugin list` shows it), it shares the lanes' codex install and login:

- **`/codex:adversarial-review`** on the accumulated diff before the `fable-advisor` final review for anything that touched a security-sensitive path, a migration, or an API shape. It or `astra-advisor` satisfies the automatic cross-vendor review; never run both. Feed its findings into the Fable consult as context. `/codex:review` is the lighter pass for deliverables below the threshold when the user wants one.
- **`/codex:rescue --model <slug> --effort <rung>`** for user-driven delegation or a long investigation off the critical path; it caps effort at `xhigh` and returns Codex's output rather than a lane report, so the architect still reads the diff and re-runs verification. For `max`/`ultra` or the structured report, use the lanes.
- **`/codex:setup`** when a lane reports `unavailable`.

Leave the plugin's stop-time review gate off under this pattern unless the user chooses otherwise; it overlaps the mandatory review and can loop. Without the plugin the pattern is unchanged.

## Verification

Reports are claims, not evidence. Before accepting any lane's work: read the diff, and re-run the verification command or spot-check its quoted output against the working tree. "Should work" or a report with no command output means the task is not done. An empty diff with a clean exit is a refusal; the lanes report it as `refused`. A lane that reports a spec gap gets a corrected spec, never "use your judgment".

**Lane objections are hypotheses, not orders.** `STATUS: contested` means the lane read the spec against the tree and found defects listed in `OBJECTIONS`; it did no work. Check each objection against the tree (the routine lane runs a weaker model and sometimes contests a sound spec), then correct the spec or answer the objection with the evidence that refutes it, and resend to the same lane with `SendMessage`. Never answer a contest with "use your judgment", never rewrite the spec to what the lane guessed, and never do the work yourself because the lane pushed back. A spec contested on three corrected versions is a decision the architect has not made; take it to `fable-advisor` before a fourth.

The lane re-runs the spec's verification commands once and quotes them; it does not replay codex's exploratory commands. Re-run the same commands yourself only after a `timeout` or `partial`, or when the quoted output disagrees with the tree; for a `complete` report with matching evidence, spot-check one command.

A lane's verification covers only what its commands parsed. Check that every touched file went through a compile, typecheck, or lint the lane ran; when the test build skips a file, run the covering check yourself. The same applies to investigation output: spot-check one number in a `data-investigator` table against the file it came from before it enters a finding.

Surface the lane's `DIAGNOSTICS:` line verbatim in your report.

**Sandbox posture is the operator's.** The codex implementation lanes pass no `--sandbox` flag; codex runs at the `sandbox_mode` in `~/.codex/config.toml`. When the key is unset, `codex exec` is read-only and every lane run fails its preflight with `unavailable`; the operator writes `sandbox_mode = "workspace-write"` or opts into `danger-full-access` through the `setup-dangerous-yolo-codex` skill. Never invoke that skill yourself; it runs only when the user types `/fable-advisor:setup-dangerous-yolo-codex` in their own turn. When a spec needs something the sandbox cannot reach, name the blocker and let the user decide.

## Harness notes

- **Waiting.** Chained `sleep` in a Bash call is blocked. To wait on CI, run `gh run watch <id> --exit-status` in a background Bash call, or an `until <check>; do sleep 20; done` loop in one background call. Poll one run id, never `gh run list` in a loop.
- **Working directory drift.** The session cwd can change after a `cd` inside a command. Use absolute paths in every command that matters and re-`cd` at the start of scripts.
- **No artifact tool.** Shareable output is a file in the repository or a temp directory, a static site the user hosts, or a markdown file with a rendering prompt at the top.
- **Background agents notify once.** A backgrounded agent's result, and a lane's reply to a `SendMessage`, arrive as task notifications; there is no blocking wait. Do not poll and do not predict the result. Never call `TaskOutput` on an agent task: its output file is the whole JSONL transcript and lands in your context. For a timer while a lane works, run `sleep N` in a background Bash call.
- **Subagents cannot receive notifications.** A lane that backgrounds a process and ends its turn is never woken, and a background Bash left running in a lane fires a stray notification into the architect's conversation after the lane has reported. The lanes launch codex detached through `scripts/lane.sh`, poll in bounded foreground calls, and never use the Bash tool's background mode.
- **Lane heartbeat.** `lane.sh status <lane>` prints `last_output_age` and `progress_lines`; the lanes use it to tell stuck from slow. The architect never reads a lane's `stdout.log`; the lane's report and `PROGRESS` line are the interface.
- **Lane scratch.** Each lane run gets a `${TMPDIR:-/tmp}/<prefix>-lane.<random>` directory and removes it once its report is written; `lane.sh init` also garbage-collects finished lane directories older than 24 hours, and `lane.sh gc [hours]` does the same on demand.
- **Temp data.** Keep investigation output under an ignored directory in the repository (`tmp/<investigation>/`) so it survives the session, stays out of git, and can be handed to a rendering lane later.
