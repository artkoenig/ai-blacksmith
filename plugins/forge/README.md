# forge

Interview issues into shape. Execute them autonomously on the smallest token budget that works.

## The split

**`/forge:issue` writes issues.** It interviews you and stores a goal, numbered acceptance criteria,
and what is out of scope. Nothing else - no file list, no plan. A map written into an issue is
maintained by nobody; the implementer finds its own way. Storage is per project: `/forge:bootstrap` writes an adapter for GitHub Issues, markdown
files, or whatever you describe.

**The same session decides the cut**, then starts the run. It is the only place that sees the whole
issue at once.

**`/forge:work` executes.** One loop per increment: implement, review, repair until the verdict
converges. The implementer commits each round; the reviewer merges the increment it passes.
Independent increments implement at the same time, each in its own worktree and branch, and are
reviewed one after another, since each review may end in a merge onto the issue branch. An uncut
issue skips all of that and works in the checkout.
No user interaction is possible during a run, by design. You get a branch and a commit; push and
pull requests stay yours.

## Why it is cheap

| Lever | What it does |
| --- | --- |
| Area notes | What is true of one directory only lives in `.claude/rules/areas/<area>.md` under a `paths:` glob, and reaches an agent by itself the first time it reads a file there. Knowledge of an area costs nothing until the agent enters it, and the implementer writes back what it learns, so the second issue in an area is cheaper than the first. |
| The workflow | The loop and every intermediate result live in script variables. Your conversation pays for the invocation and the final line. |
| Wrapper commands | `forge-test` answers `0` or `1`. Detail costs extra on purpose: `--failing`, then `--detail <id>`. |
| The guard hook | A raw `npm test` is rewritten to the wrapper before it runs, or refused with the wrapper named. |
| The compaction hook | Bash output past a line budget arrives as head + tail plus a path to the full log. stderr is never touched. |
| The cut | Cutting adds a dispatch set, so `/forge:issue` cuts only for parallelism, for a diff too large to review in one pass, or for a real dependency. |
| Pre-existing red | The reviewer proves a failing check was already failing before it spends a repair round on it. |
| Measured startup | Every agent start records what it loaded and what that cost, so a growing skill or rule shows up as a number instead of a feeling. |

## Each increment's loop ends on

- **pass** - every criterion holds. Committed.
- **stalled** - a round repeated the previous round's failed set. The implementer stopped moving.
- **cap** - eight rounds, for a verdict that oscillates. Override with `maxRounds`.

A failed increment leaves its branch standing and its dependents skipped; its independent siblings
still merge. A merge conflict is reported, never resolved.

## Commands

| Command | Does |
| --- | --- |
| `/forge:bootstrap` | One-time project setup. Run this first. |
| `/forge:issue` | Interview, write the issue, decide the cut, start the run. |
| `/forge:work <id>` | Execute an issue. Usually started for you by `/forge:issue`. |
| `/forge:new-agent` | Add a project agent for one area of the codebase. |
| `/forge:stats` | Tool calls per agent run, over time. |
| `/forge:context` | What each agent loaded at startup: measured tokens, breakdown by source, saved copies. |

## Agents

Two, on purpose.

- **`forge:implementer`** - all file, git and shell work.
- **`forge:reviewer`** - reads the issue itself, writes nothing into the checkout it judges, and
  builds throwaway worktrees outside the checkout to run checks at the base or to settle a doubt
  with a probe.

`/forge:new-agent` adds project agents from the same template. `/forge:issue` selects one per
increment.

## Install

```bash
/plugin marketplace add artkoenig/test
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

**Forge Terse** ships with `force-for-plugin: true`, so it applies while the plugin is enabled. It is
read once at session start - `/clear` or a new session to pick it up.

It does not reach subagents; Claude Code does not pass output styles into them. Agent brevity comes
from the `agent-protocol` skill.

## What it writes into your project

```
.forge/config.json                       check commands and parsers
.forge/last/                             cached raw output (gitignored)
.forge/metrics.jsonl                     one line per agent run (gitignored)
.claude/worktrees/                       one per increment of a cut issue (gitignored)
.claude/skills/issue-backend/SKILL.md    your issue storage, as commands
.claude/rules/forge.md                   the short version, loaded every session
.claude/rules/areas/<area>.md            what is true of one directory, loaded when it is read
```
