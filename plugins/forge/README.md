# forge

Interview issues into shape. Execute them autonomously on the smallest token budget that works.

`/forge:issue` interviews you and writes an issue: a goal, numbered acceptance criteria, what is out
of scope. `/forge:work` executes one, in a loop of implement and review, until the verdict
converges. Storage is per project - `/forge:bootstrap` writes the adapter.

How each of them behaves is defined in its own file, and only there. This README does not restate
it; a copy here would drift.

| Command | Defined in |
| --- | --- |
| `/forge:bootstrap` | `skills/bootstrap/SKILL.md` |
| `/forge:issue` | `skills/issue/SKILL.md` |
| `/forge:work <id>` | `workflows/work.js` |
| `/forge:new-agent` | `skills/new-agent/SKILL.md` |
| `/forge:insights <dir>` | `skills/insights/SKILL.md` |
| `/forge:stats` | `skills/stats/SKILL.md` |
| `/forge:context` | `skills/context/SKILL.md` |

## Agents

Two, on purpose - `agents/implementer.md` and `agents/reviewer.md`. `/forge:new-agent` adds project
agents from the same template.

## Where the token budget goes

The levers, each with the file that owns it:

| Lever | Owned by |
| --- | --- |
| Area notes, loaded only when their directory is read | `skills/insights/SKILL.md` |
| The loop and its intermediate results, kept in script variables | `workflows/work.js` |
| Wrapper commands that answer without a second look | `bin/` |
| The guard hook, rewriting a raw check to its wrapper | `scripts/guard-bash.js` |
| The compaction hook, withholding oversized Bash output | `scripts/compact-output.js` |
| Measured startup, per agent run | `scripts/subagent-start.js`, `scripts/subagent-metrics.js` |

`/forge:context` and `/forge:stats` read the measurements back out.

## Install

```bash
/plugin marketplace add artkoenig/ai-blacksmith
/plugin install forge@artkoenig-marketplace
```

Install at user scope - a project-scope plugin loads only after the workspace trust dialog. Then, in
the target repository: `/forge:bootstrap`.

## Requirements

- Claude Code v2.1.154 or later, workflows available on your plan. The `SubagentStart` hook behind
  `/forge:context` needs v2.1.234 or later; without it the estimate is missing and only the measured
  numbers from `SubagentStop` are recorded. On Pro, enable **Dynamic
  workflows** in `/config`. Without them there is no `/forge:work`.
- Node on `PATH`.

`/forge:bootstrap` checks these and says what breaks.

## Output style

forge ships none. Set `outputStyle` to Claude Code's built-in **Concise**, which needs v2.1.237 or
later. A style is read once at session start - `/clear` or a new session to pick it up.

What Concise does not cover - which language to answer in, English in files, `path:line`, and that
brevity never hides a blocker - lives in `rules/forge.md`, injected by the `SessionStart` hook.
That reaches subagents; an output style does not. Agent brevity comes from the `agent-protocol`
skill.

## What it writes into your project

```
.forge/config.json                       check commands and parsers
.forge/last/                             cached raw output (gitignored)
.forge/metrics.jsonl                     one line per agent run (gitignored)
.claude/worktrees/                       one per increment of a cut issue (gitignored)
.claude/skills/issue-backend/SKILL.md    your issue storage, as commands
.claude/rules/areas/<area>.md            what is true of one directory, loaded when it is read
                                         written by /forge:insights
```
