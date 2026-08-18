# Developing forge

`plugins/forge/` is the source. The repository is set up to build forge with forge: `.claude/`
symlinks the components into project scope, so a session at the repo root uses them directly as
skills and agents, from the working tree.

```
.claude/agents/*.md          -> plugins/forge/agents/*.md
.claude/skills/*             -> plugins/forge/skills/*
.claude/workflows/work.js    -> plugins/forge/workflows/work.js
.claude/settings.json         registers the hooks by path
.claude/skills/issue-backend  this repository's own adapter - GitHub Issues, not a symlink
.forge/config.json            forge-test runs test.sh
.forge/context.jsonl          one line per agent start, plus copies under .forge/context/ (both ignored)
.claude/agent-memory/         the implementer's map of this project - tracked, and it must stay tracked
```

Edit the file under `plugins/forge/`. Never edit through the symlink path.

## Names lose the `forge:` prefix

Used directly rather than installed, the components are project-scope:

| Installed | Here |
| --- | --- |
| `/forge:issue` | `/issue` |
| `/forge:work` | `/work` |
| `forge:implementer` | `implementer` |

So run the workflow with `agentPrefix: ""`:

```
/work {"issue": "3", "agentPrefix": ""}
```

The agents list both `forge:agent-protocol` and `agent-protocol` in `skills:`; a missing one is
skipped with a warning, so the preload works either way. Supporting files are addressed with
`${CLAUDE_SKILL_DIR}`, which substitutes in both.

## What updates without a restart

| Component | Live? |
| --- | --- |
| `skills/*/SKILL.md` | yes - Claude Code watches `.claude/skills/` ([docs](https://code.claude.com/docs/en/skills#live-change-detection)) |
| `agents/*.md` | yes, within seconds - it watches `.claude/agents/` ([docs](https://code.claude.com/docs/en/sub-agents)) |
| `scripts/*.js` | yes - hook scripts are read at execution |
| `workflows/work.js` | expected, undocumented - the script is read when the workflow runs |
| Hook registration in `.claude/settings.json` | expected, undocumented - `ConfigChange` fires for settings files |
| `output-styles/*` | no - part of the system prompt. `/clear` |

A directory that did not exist when the session started is not watched. After adding the first file
to a new one, restart.

## Checks

```bash
./test.sh          # six suites, no Claude Code session needed
forge-test         # the same, through the wrapper: 0 or 1
```

`test.sh` covers the manifest and syntax, the wrapper contract against a fixture project, every hook
decision, the startup measurement against a fixture agent and a synthetic transcript, that the agent memory
is tracked and inside its budget, and the workflow's control flow against stubbed agents - wave order, stall detection,
skipped dependents, merge conflicts, a missing issue id.

## Where an agent's transcript lives

Verified on 2.1.234, by running an agent: `SubagentStart` and `SubagentStop` both fire for
`Task`-spawned agents with hooks registered in project settings, and the path a `SubagentStop` hook
is handed is the *session's* transcript, not the agent's. The agent's own file is

```
<project>/<session-id>/subagents/agent-<agent-id>.jsonl
```

and every entry in it carries `agentId`. `subagent-metrics.js` derives that path and refuses to
measure anything it cannot attribute by `agentId` - measuring the file it was handed would report
the session's tokens and tool calls under the agent's name. A missing number is the expected
failure; a wrong one is not. The estimate from `SubagentStart` reads files, not the transcript, so
it holds either way.

## Auto memory in this session

`memory: project` resolves to `.claude/agent-memory/<agent>/`, the scope the docs call shareable via
version control, so `.claude/agent-memory/implementer/MEMORY.md` is tracked and reaches every
checkout.

It reached no agent until `CLAUDE_CODE_REMOTE_MEMORY_DIR` was set. Auto memory is on by default, but
a cloud session turns it off unless that variable names a directory, and subagent memory is part of
auto memory: without it the agent launches with neither the memory instructions nor the memory tool.
`.claude/settings.json` now sets it in its `env` block, which is the route the docs give for
configuring a cloud session from the repository. The change applied to the running session - no
restart.

Measured, same probe each time. The last column is `start` minus the sources - the system prompt,
the tool schemas, and whatever else the harness adds:

| | `memory:` | start | est | harness |
| --- | --- | --- | --- | --- |
| implementer, before the memory existed | project | 11475 | 971 | 10504 |
| implementer, memory on disk, auto memory off | project | 11504 | 1040\* | 10464 |
| implementer, auto memory on | project | 16660 | 1680 | 14980 |
| reviewer, auto memory on | none | 11509 | 1229 | 10280 |

\* the 640-token index is out of `est` in that row: it was on disk and nothing read it.

An agent that declares `memory:` pays about 4.5k tokens for the memory instructions and the tool
schemas, on top of the index itself. An agent without the field pays none of it: the reviewer's
harness budget sits within 200 tokens of the implementer's with memory off, and asked directly it
answered that no `MEMORY.md` reached it. Omitting the field is the only switch - the docs give no
`memory: false`.

So the price is per agent, not per session. For the implementer the map has to save more than 5k
tokens a run, roughly two searches. The reviewer stays cheap by design, and its `You have no memory`
line is now a measured fact rather than an intention.

## Still unverified

Neither has been observed in a real session:

- Whether `agentType: 'forge:implementer'` resolves a plugin-scoped agent inside a workflow. Here
  the unprefixed names are used instead, so this stays open until someone runs an installed copy.
- Whether plugin hooks fire inside workflow-spawned agents. Here the hooks come from project
  settings rather than the plugin, so this stays open too.

