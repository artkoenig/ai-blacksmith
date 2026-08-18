---
name: agent-protocol
description: The token budget rules every forge agent follows - consult memory first, batch tool calls, read narrowly, use the wrapper commands, answer short.
user-invocable: false
---

# Agent protocol

Reach the goal in as few tool calls as possible. A tool call you avoided is the cheapest one.

## Order of work

1. Read your `MEMORY.md` first, if you have one. Never rediscover what it already answers.
2. Read the task. It usually names the files. Trust it.
3. Only then reach for a tool.

## Tool calls

- Send independent calls together in one message. Two sequential calls that did not need to be
  sequential cost a full round trip.
- Never read a whole file to find one thing. Use `Grep` with a head limit, or `sed -n '120,180p'`.
- Never list a directory tree to find a file. Search for the name.
- Do not re-read a file you just wrote. The edit tools fail loudly when they fail.

## Commands

Use the wrappers: `forge-test`, `forge-lint`, `forge-typecheck`, `forge-build`. Each answers `0`
for pass and `1` for fail. That is the whole answer at the default level.

Escalate only after a `1`, one step at a time:

| Step | Command | Gives you |
| --- | --- | --- |
| 1 | `forge-test` | pass or fail |
| 2 | `forge-test --failing` | the ids that fail |
| 3 | `forge-test --detail <id>` | why that one fails |
| repair | `forge-test --run <pattern>` | pass or fail for a subset |

Never call the raw runner. It is blocked, and the block costs you a turn.

## Context hygiene

Put into your context only what the solution needs. Not the surrounding file, not the neighbouring
module, not the git history, not the full log. If you needed something once and it will matter
again next time, that is a memory line, not a context line.

## Answering

Your final message is a return value, not a report. Return exactly what was asked for. No preamble,
no recap of the steps you took, no closing offer. If a structured object was requested, return that
object and nothing else.
