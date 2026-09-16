---
name: computer-use
description: Doctrine for browser and computer-use work under the architect-as-orchestrator pattern — route every browser task (UI verification, visual checks, screenshots, login flows, drag-and-drop, browser E2E, "use Astra") to the `astra-operator` agent, which runs GPT-6 Astra through Codex with an isolated headless Playwright Chrome MCP server. Covers resolving the real application URL first, writing the browser brief, what counts as browser evidence, secrets in login flows, cleanup, and how the same lane extends to desktop computer use. USE WHEN a task needs a real browser or desktop interaction, when verifying a UI change, when the user says "use Astra", or when deciding whether a shell probe or a host preview browser is an acceptable substitute (it is not, unless the user chose it).
---

# Computer use — the browser lane doctrine

The session is the architect. It does not drive a browser itself, and it does not accept a shell `curl` as proof that a UI works. Browser and computer-use work goes to a subagent that runs **GPT-6 Astra**, because Astra is currently the strongest model at operating a real browser: it reads accessibility trees and screenshots reliably, recovers from layout surprises, and completes multi-step flows that other models abandon. Routing there is a capability decision, the same way the codex lanes are a capability-and-cost decision in the orchestration skill.

## Route here when

- Verifying that a UI change works in the running application, not just in tests.
- Visual checks, screenshots for a PR, layout regressions.
- Login flows, session persistence, anything that depends on cookies, TLS, secure-context APIs, or WebSockets.
- Drag-and-drop, keyboard navigation, file pickers, and other interactions that DOM-level tests fake.
- Browser end-to-end runs that are not (yet) a checked-in deterministic suite.
- The user says "use Astra".

Do not route here for checked-in deterministic browser suites: those run their own Playwright scripts directly, in CI and locally, and must not invoke a model. The lane is for interactive verification.

## The lane

| Lane | Producer | Invoke | Notes |
|---|---|---|---|
| Browser / computer use | GPT-6 Astra (effort `medium` by default) | `astra-operator` agent | Standalone `codex exec` with the `playwright_chrome` MCP server enabled for that run only. Headless, isolated context, no desktop session needed. Requires the codex CLI and a configured browser server. |

The lane never substitutes. If it returns `unavailable`, the fix is on the host (codex login, `playwright_chrome` config, installed browser), not a different model. A host-provided preview browser (an IDE or agent-host tab you can drive from the session) is an alternative only when the user explicitly chooses it; it runs on whatever client is connected, its `localhost` is not necessarily the shell host, and its evidence lives in a different place. Say which workflow ran.

## Resolve the application first — architect work

The brief carries the exact URL. Producing it is the architect's job, before the delegation:

- For a local application, get the URL from the project's own tooling (a dev-server launcher, a worktree tool, a printed dev-server banner). Use the resolved scheme, host, port, and path as given.
- For a deployed application, use the task's authorized stage or the explicit URL the user gave. Do not stand up a local stack to reproduce a reported deployed failure unless asked.
- Never guess `localhost:3000`, a port from memory, or a hostname. Never rewrite an HTTPS URL to HTTP or loopback because the browser runs headless on the shell host: origin decides cookies, TLS, `isSecureContext`, WebSockets, and hot reload, and a loopback run proves a different application than the one under test.
- A shell health probe on an internal endpoint establishes readiness. It is not browser verification and does not appear in the report as such.
- If the project has more than one runtime (a compiled product build versus local source, a launcher-started product build versus a dev server), name which one the URL points at, and make sure it is the one the change lives in.

## Writing the brief

The operator shares none of your context. The brief is the six-part spec of the orchestration skill, shaped for a browser:

1. **Objective** — the behaviour under test, one paragraph, and the expected visible result.
2. **Target** — the exact authorized URL and which runtime it is. Artifacts live in the operator's own scratch dir; the brief never names a checkout as the working directory.
3. **Steps** — real UI steps: what to click, type, drag, in what order; any reload or persistence check; what may be mutated and what may not.
4. **Login** — the authorized flow if needed, and the path of the 0600 credential file the lane splices into the prompt (one secret per file, written outside any repository, by the architect or a runner that never echoes it). Otherwise "none".
5. **Evidence** — what to return: observed origin, per-step outcome, screenshots of which states, console errors, persistence after reload.
6. **Reasoning** — `REASONING: medium` unless a flow is unusually long or fragile; the operator passes it through.

A brief you cannot finish writing is a signal the acceptance criterion is not decided yet. Decide it; do not hand the ambiguity to the browser.

## What counts as evidence

Reports are claims. The operator already checks the events file and screenshots before reporting; the architect reads its report with the same stance:

- **Origin matched.** The observed origin equals the briefed URL, scheme included.
- **Real input.** Each step maps to a click, keyboard, or drag tool call. A step done through page evaluation that mutated state, dispatched synthetic events, wrote storage, or called `fetch` is not a pass; the operator marks it "via evaluate only" and the architect treats it as a failure of that step.
- **Screenshots show the expected state.** Look at them. A "done" claim over an error page or a login wall is a failure.
- **Persistence, when it matters.** Reload happened and the post-reload state was inspected.
- **Authenticated scope.** A page that loads without login proves nothing about authenticated behaviour. The report says which steps ran authenticated.
- **Fixture versus application.** A synthetic page or a component fixture proves the driver works, never that the application feature works. Report fixture coverage separately from application coverage.

Navigation alone, an HTTP 200, or an exit-zero worker are not evidence of the requested interaction.

## Secrets in login flows

- Credentials, verification codes, cookies, and bearer tokens never appear in the brief as plain text you copied from somewhere, in CLI arguments, in the report, or in screenshots. They reach the worker only as a 0600 file named in the brief, which the operator splices into the prompt with `cat` and shreds with the prompt and events afterwards; the architect never reads the value into its context either. The operator strips credential-bearing tool arguments before keeping evidence.
- Existing authorized identities and the normal side effects of logging in need no new permission. A new identity, a password reset, or a change to another user's state does.
- Never screenshot a filled password or code field. Screenshots the user might share further are sanitized first; the architect decides what leaves the machine, and the operator only lists paths.

## Cleanup and side effects

- The operator stops every process the run owned: codex, the MCP server, Chrome. It never ends its turn with any of them running.
- `--ephemeral` does not guarantee zero config changes: recent Codex versions persist a project-trust entry for the run's working directory. The operator removes only an exact task-created entry and preserves the rest.
- Browser transcripts, events, and screenshots stay in the operator's scratch dir outside any repository until the architect has read what it needs. They are never committed and never uploaded implicitly.
- If the task created a test stack or a test worktree, the project's own cleanup policy applies after the report.

## Beyond the browser: desktop computer use

The same lane extends to desktop automation when a computer-use MCP server (screen capture plus mouse and keyboard) is configured on the host. The doctrine is unchanged: the architect resolves the target and writes the brief; the operator enables that server for the run, requires real input, treats the screenshot sequence as evidence, and cleans up. Two additions:

- The preflight must confirm a display or virtual display exists; headless Chrome needs none, a desktop session does.
- Blast radius is larger. A browser run is confined to one isolated context; a desktop run can reach every window. The brief names the application and the windows it may touch, and forbids everything else.

Treat the desktop path as documented but untested until the host has run it once against a synthetic target; the operator says so in `GAPS` the first time it is used.

## Verification

Before accepting the operator's report: read the `STEPS` and `EVIDENCE` lines, open at least one screenshot yourself, confirm the origin line matches the URL you briefed, and check `CLEANUP`. A report with `partial`, an evaluate-only step, or a mismatched origin is not done; either the application is wrong, the brief was wrong, or the environment is wrong, and the architect decides which before re-briefing. Surface `GAPS` and `DIAGNOSTICS` verbatim in your own report.
