# forge

Interview issues into shape, then execute them autonomously on the smallest possible token budget.

## The split

**You and the main conversation write issues.** `/forge:issue` interviews you, finds the code the
change touches while you are there to correct it, and stores an issue with numbered acceptance
criteria and a `Context` block. How issues are stored is up to the project: `/forge:bootstrap`
writes an adapter skill for GitHub Issues, markdown files, or anything else you describe.

**A workflow executes them.** `/forge:work <id>` runs `implementer → reviewer → repair → commit` as
a script. No user interaction is possible during a run, by design. The result is a branch and a
commit; push and pull requests stay your call.

## Why it is cheap

| Lever | What it does |
| --- | --- |
| The interview | The expensive exploration happens once, with you present, and lands in the issue. The implementer starts with the answer instead of searching. |
| The workflow | The loop and every intermediate result live in script variables, not in a context window. Your conversation pays for the invocation and the final line. |
| Wrapper commands | `forge-test` answers `0` or `1`. Details cost extra on purpose: `--failing`, then `--detail <id>`. |
| The guard hook | A raw `npm test` is rewritten to the wrapper before it runs, or refused with the wrapper named. |
| The compaction hook | Bash output past a line budget reaches the agent as head + tail plus a path to the full log. stderr is never touched. |
| Agent memory | The implementer's project map is committed to `.claude/agent-memory/` and grows. The second issue in an area costs almost no exploration. |

## Commands

| Command | Does |
| --- | --- |
| `/forge:bootstrap` | One-time project setup. Run this first. |
| `/forge:issue` | Interview, then write one issue. |
| `/forge:work <id>` | Execute one issue autonomously. |
| `/forge:new-agent` | Add a project agent with its own memory. |
| `/forge:stats` | Tool calls per agent run, over time. |

## Agents

Two, on purpose.

- **`forge:implementer`** - `memory: project`. Does all file, git and shell work. Records the
  project map as it goes, so it stops rediscovering it.
- **`forge:reviewer`** - no memory, on purpose. A reviewer that remembers its own verdicts drifts
  toward confirming them. Every round gets a fresh one.

`/forge:new-agent` adds project agents from the same template when an area deserves its own memory.

## Install

```bash
/plugin marketplace add artkoenig/test
/plugin install forge@artkoenig-marketplace
```

Install at user scope. A project-scope plugin loads only after the workspace trust dialog.

Then, in the target repository:

```
/forge:bootstrap
```

## Requirements

- Claude Code v2.1.154 or later, and workflows available on your plan. On Pro, enable **Dynamic
  workflows** in `/config`. Without workflows there is no `/forge:work`.
- Auto memory enabled. With it off, the `memory:` field does nothing and the agents relearn the
  project every run.
- Node on `PATH`. The wrappers and hook scripts use it.

`/forge:bootstrap` checks both preconditions and tells you what breaks if one is missing.

## Output style

The plugin ships **Forge Terse** with `force-for-plugin: true`, so it applies while the plugin is
enabled. It is read once at session start, so it takes effect after `/clear` or in a new session.

It does not reach subagents - Claude Code does not pass output styles into them. Agent brevity comes
from the `agent-protocol` skill instead.

## What it writes into your project

```
.forge/config.json                       check commands and parsers
.forge/last/                             cached raw output (gitignored)
.forge/metrics.jsonl                     one line per agent run (gitignored)
.claude/skills/issue-backend/SKILL.md    your issue storage, as commands
.claude/rules/forge.md                   the short version, loaded every session
.claude/agent-memory/implementer/        project knowledge - commit this
```
