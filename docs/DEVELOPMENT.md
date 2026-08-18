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
./test.sh          # five suites, no Claude Code session needed
forge-test         # the same, through the wrapper: 0 or 1
```

`test.sh` covers the manifest and syntax, the wrapper contract against a fixture project, every hook
decision, the startup measurement against a fixture agent and a synthetic transcript, and the
workflow's control flow against stubbed agents - wave order, stall detection,
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

## Still unverified

Neither has been observed in a real session:

- Whether `agentType: 'forge:implementer'` resolves a plugin-scoped agent inside a workflow. Here
  the unprefixed names are used instead, so this stays open until someone runs an installed copy.
- Whether plugin hooks fire inside workflow-spawned agents. Here the hooks come from project
  settings rather than the plugin, so this stays open too.

