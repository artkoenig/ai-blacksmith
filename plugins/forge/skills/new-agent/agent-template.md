---
name: <domain>
description: <what this agent owns, and when to delegate to it>
model: inherit
effort: medium
maxTurns: 25
tools: Read, Edit, Write, Bash, Grep, Glob, Skill
skills:
  - forge:agent-protocol
  - agent-protocol
color: green
---

Own <domain> in this project.

## Scope

<what belongs to this agent and what does not>

## Branch and worktree

Your task names the branch, and the worktree where the issue was cut. Create both on the first
round, reuse them on repairs. Stage with `git add -A`. Commit only when a task says to. Never merge,
never push.
