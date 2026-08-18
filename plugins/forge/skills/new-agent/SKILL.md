---
name: new-agent
description: Create a project-specific subagent that builds its own memory. Use when one area of the codebase keeps coming up and deserves an agent that remembers it.
argument-hint: "[domain, e.g. api or db-schema]"
allowed-tools: Read, Write, Grep, Glob, AskUserQuestion
---

# Create a project agent

Add one where an area is distinct enough that its knowledge should not sit in the implementer's
index: a separate stack, a separate service, a domain with its own rules.

Never add one just to have one. Every agent is another index to keep under 200 lines.

## 1. Scope

Ask the user what the agent owns and what it does not. Overlap with another agent means the split
is wrong.

## 2. Write it

Copy `${CLAUDE_PLUGIN_ROOT}/templates/agent.md` to `.claude/agents/<domain>.md`:

- `name`: the domain, kebab-case.
- `description`: what it owns and when to delegate to it. Routing reads this.
- `tools`: the minimum. Drop `Write` where it only edits, `Bash` where it runs nothing.
- `maxTurns`: a real ceiling.
- `memory: project` stays.

## 3. Seed the memory

Write `.claude/agent-memory/<domain>/MEMORY.md` with what this conversation already knows: where
the domain's code lives, which command exercises it, which conventions apply. One line per fact.

An empty index costs the agent its first run rediscovering what was on screen.

## 4. Report

The file, the domain, the one-line description. Nothing else.

`/forge:issue` selects the agent per increment with `agent: "project:<domain>"`. Nothing in an issue
names one.
