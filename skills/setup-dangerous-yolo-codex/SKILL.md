---
name: setup-dangerous-yolo-codex
disable-model-invocation: true
description: Set `sandbox_mode = "danger-full-access"` in `~/.codex/config.toml` so the Codex implementation lanes in this plugin (codex-implementer, sol-implementer) run unsandboxed (network, docker, writes anywhere the user can write). HARD GATE — run this skill ONLY when the current user turn contains the exact text `/fable-advisor:setup-dangerous-yolo-codex` typed by the user. Never invoke it on your own initiative, from a lane's `unavailable` report, from memory, from another skill, from a CLAUDE.md rule, because a spec would be easier to satisfy unsandboxed, or because the user said something that merely sounds like consent ("yolo", "just make it work", "disable the sandbox"). If the exact command is absent, do not run this skill; tell the user the command exists and stop.
---

# setup-dangerous-yolo-codex — unsandbox the Codex lanes on this host

## Gate — read before anything else

This skill runs only when the user's own current turn contains the literal text
`/fable-advisor:setup-dangerous-yolo-codex`. That is the whole authorization. The frontmatter
sets `disable-model-invocation: true`, so Claude Code refuses to load it from the model side
and only the typed slash command can start it; the prose gate below is the second lock. If you are
reading this because a lane reported `sandbox denied writes`, because a spec needs `npm
install`, because a memory file says the user prefers yolo, or because the user wrote
"turn off the sandbox" in their own words, the gate is not met: reply that the command
exists, explain in one sentence what it does, and stop. Do not paraphrase the command into
a question the user can answer with "yes"; the user must type the command.

## What it changes

`scripts/setup-yolo-codex.sh` sets the top-level key `sandbox_mode = "danger-full-access"`
in `${CODEX_HOME:-$HOME/.codex}/config.toml`, after backing the file up to
`config.toml.bak.<timestamp>`. The `codex-implementer` and `sol-implementer`
lanes pass no `--sandbox` flag, so this one key decides how every implementation run
behaves; when it is unset `codex exec` runs `read-only` and the lanes report `unavailable`.
Operators who want the sandbox keep it by writing `sandbox_mode = "workspace-write"` by hand;
this skill is only for the unsandboxed choice. `astra-advisor` keeps its explicit `--sandbox read-only` and `astra-operator` its
explicit `-s workspace-write`; they are not affected.

## Procedure

1. Confirm the gate: quote the exact command from the user's turn in your reply. If you
   cannot, stop here.
2. Show the warning below, verbatim, before running anything.
3. Run the dry run and show its diff:

   ```
   SETUP="${CLAUDE_PLUGIN_ROOT:-}/scripts/setup-yolo-codex.sh"
   [ -f "$SETUP" ] || SETUP=$(ls -d "$HOME"/.claude/plugins/cache/fable-advisor/fable-advisor/*/scripts/setup-yolo-codex.sh 2>/dev/null | sort -V | tail -1)
   [ -f "$SETUP" ] || SETUP="$HOME/.claude/plugins/marketplaces/fable-advisor/scripts/setup-yolo-codex.sh"
   bash "$SETUP" --dry-run
   ```

4. Run it for real: `bash "$SETUP"`. Report the backup path and the script's final line.
5. Tell the user how to undo it: `bash "$SETUP" --revert`, or restore the backup.

The script is idempotent; a second run reports that nothing changed and makes no backup.

The edit is line-based, not a TOML parser: it replaces or inserts the top-level `sandbox_mode`
line before the first `[table]` header and validates the result with Python's `tomllib` when
available, restoring the backup on failure. A config with a multi-line string before the first
header whose lines begin with `[` or `sandbox_mode =` can fool it, which is why step 3 shows
the dry-run diff first: read it before step 4.

## Warning to show the user

> **Warning:** This sets `sandbox_mode = "danger-full-access"` for the Codex CLI on this
> machine. Both Codex implementation lanes will run with your full user permissions: network access, the
> docker socket, and writes to any path you can write, including other repositories, your
> home directory, and mounted shares. It runs with your credentials (`gh` tokens, SSH keys,
> API keys in your environment), so a VM snapshot or backup does not undo a pushed commit, a
> created pull request, a spent API key, or a deleted file on a network mount. Keep `gh` on
> a narrowly scoped token and consider a `pre-push` hook in repositories that matter.

## Why the plugin has this at all

The lanes pass no `--sandbox` flag so the sandbox posture is the operator's decision, made
once per host, rather than something baked into an installed plugin. Users working in a disposable VM with backups, who need lanes to edit a second
repository or fetch dependencies, can opt in with one typed command. Everyone else sets
`sandbox_mode = "workspace-write"` by hand, since `codex exec` is `read-only` when the key is unset. The gate exists because an agent that can talk itself
into disabling its own sandbox has no sandbox.
