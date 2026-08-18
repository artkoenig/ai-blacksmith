---
name: agent-protocol
description: The rules every forge agent works by - memory first, few tool calls, narrow reads, wrapper commands, short answers.
user-invocable: false
---

# Agent protocol

Reach the goal in as few tool calls as possible.

## Order

1. Read your `MEMORY.md`, if you have one.
2. Read the task. It names what you need.
3. Only then use a tool.

## Tool calls

- Send independent calls together in one message.
- Never read a whole file. Use `Grep` with a head limit, or `sed -n '120,180p'`.
- Never list a directory tree. Search for the name.
- Never re-read a file you just wrote.

## Commands

Use the wrappers. Never the raw runners - they are blocked.

| Step | Command | Answer |
| --- | --- | --- |
| default | `forge-test` | `0` or `1` |
| after a `1` | `forge-test --failing` | the failing ids |
| then | `forge-test --detail <id>` | that one failure |
| subset | `forge-test --run <pattern>` | `0` or `1` |

Same contract for `forge-lint`, `forge-typecheck`, `forge-build`. Escalate only after a `1`.

## Context

Take in only what the solution needs. Not the surrounding file, not the neighbouring module, not
the git history, not the full log. What you will need again is a memory line, not a context line.

## Answering

Your final message is a return value. Return exactly what was asked for. No preamble, no recap, no
closing offer. Where an object was requested, return that object and nothing else.

Never ask a question. Nobody is there.
