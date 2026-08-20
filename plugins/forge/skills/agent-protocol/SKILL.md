---
name: agent-protocol
description: The rules every forge agent works by - area notes, few tool calls, narrow reads, wrapper commands, short answers.
user-invocable: false
---

# Agent protocol

Reach the goal in as few tool calls as possible.

## Project rules

The rules forge works by are one file, and it is attached here rather than repeated:

@${CLAUDE_PLUGIN_ROOT}/rules/forge.md

## Order

1. Read the task. It names what you need.
2. Only then use a tool.

## Area notes

What is true of one directory only lives in `.claude/rules/areas/<area>.md`, under a `paths:` glob.
Such a note arrives on its own, in a `system-reminder`, the first time you `Read` a file the glob
matches. It is the answer to the research you would otherwise do.

- `Read` triggers a note. `Grep`, `Glob` and `cat`/`sed` through Bash do not.
- `Edit` needs a `Read` first, so a file you change hands you its note before you change it.
- Entering an area you only inspect: one narrow `Read` there, with `offset` and `limit`, buys the
  note for the rest of the run.
- A note that is wrong or thin is yours to fix, if you have `Skill` and `Write`: run the
  `forge:insights` skill with that directory, the same round you learned it.

## Tool calls

- Send independent calls together in one message.
- Never read a whole file. `Read` with `offset` and `limit`, `Grep` with a head limit, or
  `sed -n '120,180p'`.
- Never list a directory tree. Search for the name.
- Never re-read a file you just wrote.

## Commands

Use the wrappers. Never the raw runners - they are blocked.

| Command | Exit | Answer |
| --- | --- | --- |
| `forge-test` | `0` | one line: `<n>/<n> tests succeeded` |
| `forge-test` | `1` | every failing test, each with its detail |
| `forge-test --run <pattern>` | `0` or `1` | the same two answers for a subset |

Same contract for `forge-lint`, `forge-typecheck`, `forge-build`. There is nothing to escalate to:
a `1` already carries what a fix needs. Exit `2` means the step could not run - unconfigured, or a
flag that does not exist. Never re-run a check to see more; you already saw everything.

## Context

Take in only what the solution needs. Not the surrounding file, not the neighbouring module, not
the git history, not the full log. What you will need again is an area note, not a context line.

## Answering

Your final message is a return value. Return exactly what was asked for. No preamble, no recap, no
closing offer. Where an object was requested, return that object and nothing else.

Write English into every file, commit message and issue, whatever language the task is written in.

Never ask a question. Nobody is there.
