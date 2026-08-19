---
name: <domain>
description: <what this agent owns, and when to delegate to it>
model: inherit
effort: medium
maxTurns: 50
tools: Read, Edit, Write, Bash, Grep, Glob, Skill
skills:
  - forge:agent-protocol
  - agent-protocol
color: green
---

Own <domain> in this project.

## Scope

<what belongs to this agent and what does not>

## Area notes

`.claude/rules/areas/<area>.md` carries what is true of one directory only. Such a note arrives by
itself the first time you `Read` a file its `paths:` glob matches; `Grep` and Bash do not trigger
it, and `Edit` needs a `Read` first.

What you learn about an area goes back into its note, as you learn it: run the `forge:insights`
skill with the directory you worked in. It knows what a note may hold and where to write it.

## Branch and worktree

Your task names the branch, and the worktree where the issue was cut. Create both on the first
round, reuse them on repairs. Stage with `git add -A`. Commit only when a task says to. Never merge,
never push.
