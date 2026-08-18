---
name: issue
description: Interview the user and write one issue with verifiable acceptance criteria and a precomputed context block. Use when the user wants to capture work, plan a change, or file a ticket.
argument-hint: "[short description of the work]"
allowed-tools: Read, Grep, Glob, Bash, Write, AskUserQuestion
---

# Write an issue

You are interviewing a human who is present right now. That is the one moment when asking is
cheaper than searching. Use it: everything you settle here, the autonomous run does not have to
rediscover.

## 1. Interview

Start from what the user said. Ask only what changes the outcome, in as few rounds as possible:

- What is true when this is done? One sentence.
- How would you check it? Push for something runnable. A criterion nobody can check is a criterion
  the reviewer will fail.
- What must not change?

Do not ask what you can read from the codebase.

## 2. Find the context now

Locate the code the change touches, while the human is here to correct you. Search narrowly:
`Grep` with a head limit, never a full-tree listing. Name files with line ranges.

This block is the single biggest token saving in the whole plugin. The implementer trusts it and
does not explore. A wrong `files:` line costs more than a missing one, so confirm anything you are
unsure about with the user rather than guessing.

## 3. Write it

Use `${CLAUDE_PLUGIN_ROOT}/templates/issue.md` verbatim as the structure:

- **Goal** - one sentence.
- **Acceptance criteria** - numbered `AC1`, `AC2`, … Each is one verifiable statement. Append
  `| verify: <command>` wherever a command can decide it, preferring
  `forge-test --run <pattern>`.
- **Context** - `files:` with line ranges, `touch-only:` with the paths the implementer may edit,
  `agent:` naming `forge:implementer` or a project agent.
- **Out of scope** - what must not change.

Split the work into several issues when the criteria do not fit on one screen. A large issue makes
the implementer explore, which is exactly what this design avoids.

## 4. Store it

Persist through the project's `issue-backend` skill. If that skill does not exist yet, stop and say
`/forge:bootstrap` has not run.

Report the issue id and one line per acceptance criterion. Nothing else.
