---
name: new-agent
description: Create a project-specific subagent that builds its own memory. Use when one area of the codebase keeps coming up and deserves an agent that remembers it.
argument-hint: "[domain, e.g. api or db-schema]"
allowed-tools: Read, Write, Grep, Glob, AskUserQuestion
---

# Create a project agent

The plugin ships two agents: `forge:implementer` and `forge:reviewer`. Add a project agent when an
area is distinct enough that its knowledge should not be mixed into the implementer's memory index -
a separate stack, a separate service, a domain with rules of its own.

Do not add one just to have one. Every agent is another memory index to keep under 200 lines.

## 1. Settle the scope

Ask the user what the agent owns and what it does not. A domain that overlaps another agent's is a
sign the split is wrong.

## 2. Write the agent

Copy `${CLAUDE_PLUGIN_ROOT}/templates/agent.md` to `.claude/agents/<domain>.md` and fill it in:

- `name`: the domain, kebab-case.
- `description`: what it owns and when to delegate to it. This is what routing reads.
- `tools`: the minimum. Drop `Write` if the agent only edits, drop `Bash` if it never runs anything.
- `maxTurns`: a real ceiling, not a round number you did not think about.
- `memory: project` stays. It is the whole reason to create an agent.

## 3. Seed the memory

Write `.claude/agent-memory/<domain>/MEMORY.md` with what you already know from this conversation:
where the domain's code lives, which command exercises it, which conventions apply. One line per
fact.

Seeding matters. An agent that starts with an empty index spends its first run rediscovering what
was already on screen.

## 4. Report

Name the file, the domain, and the one-line description. Nothing else.
