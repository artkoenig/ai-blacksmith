# implementer memory - forge

The map of this project. One line per durable fact. Index only, under 200 lines.

## What this repository is

- The forge plugin, developed with forge. Source is `plugins/forge/`; everything else consumes it.
- `.claude/agents`, `.claude/skills`, `.claude/workflows` are symlinks into `plugins/forge/`.
  Edit the file under `plugins/forge/`, never through the symlink path.
- Components lose the `forge:` prefix here: `/issue`, `/work`, `implementer`. Run the workflow with
  `agentPrefix: ""`.
- Issues live on GitHub. `.claude/skills/issue-backend/SKILL.md` is this project's adapter.

## Where things live

- `plugins/forge/agents/*.md` - implementer and reviewer. Front matter carries `memory:` and `skills:`.
- `plugins/forge/skills/<name>/SKILL.md` - one directory per skill. `${CLAUDE_SKILL_DIR}` addresses
  supporting files.
- `plugins/forge/scripts/*.js` - hook scripts. `lib.js` holds `readInput`, `projectRoot`, `config`, `emit`.
- `plugins/forge/bin/*` - wrapper commands. `forge-run` is the shared implementation; the rest `exec` into it.
- `plugins/forge/workflows/work.js` - the run loop. Every intermediate result stays in a script variable.
- `docs/DEVELOPMENT.md` - what updates without a restart, and what is still unverified.

## Conventions that bite

- A hook is registered twice: `plugins/forge/hooks/hooks.json` for an installed copy, and
  `.claude/settings.json` by path for this repository. Both, or it does not fire here.
- Hook scripts never block and never throw. Wrap the work in `try`, end with `emit(null)`.
- Wrapper commands answer `0` or `1`; detail costs an extra call on purpose.
- `forge-test` is on `PATH` only where the plugin is installed. Here: `plugins/forge/bin/forge-test`.
- Prose in this repo is terse and reasons once. No em dashes; ` - ` instead.

## Checks

- `bash ./test.sh` runs every suite without a Claude Code session. `forge-test` wraps it.
- A suite is a `# --- <name> ---` block that prints `ok <name>` or `fail <name> "<what>"`.
- Fixtures are `mktemp -d` projects carrying their own `.forge/config.json`.

## Runtime facts

- Agent transcripts: `<project>/<session-id>/subagents/agent-<agent-id>.jsonl`, every entry carries
  `agentId`. The path a `SubagentStop` hook is handed is the session's, not the agent's.
- `.forge/metrics.jsonl` (one line per agent stop) and `.forge/context.jsonl` plus `.forge/context/`
  (one record and a copy set per agent start) are local, gitignored.
- This file is tracked. Write it inside your worktree so `git add -A` commits it.
