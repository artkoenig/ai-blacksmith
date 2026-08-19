---
name: new-agent
description: Create a project-specific subagent for one area of the codebase. Use when an area keeps coming up and deserves an agent with its own scope and rules.
argument-hint: "[domain, e.g. api or db-schema]"
allowed-tools: Read, Write, Grep, Glob, AskUserQuestion
---

# Create a project agent

Add one where an area is distinct enough to carry its own scope: a separate stack, a separate
service, a domain with its own rules.

Never add one just to have one. Every agent is another definition to keep current.

## 1. Scope

Ask the user what the agent owns and what it does not. Overlap with another agent means the split
is wrong.

## 2. Write it

Copy `${CLAUDE_SKILL_DIR}/agent-template.md` to `.claude/agents/<domain>.md`:

- `name`: the domain, kebab-case.
- `description`: what it owns and when to delegate to it. Routing reads this.
- `tools`: the minimum. Drop `Write` where it only edits, `Bash` where it runs nothing.
- `maxTurns`: a real ceiling.

## 3. Write down what the domain needs

The agent carries nothing between runs. Put what it must know - where the domain's code lives,
which command exercises it, which conventions apply - in an area note: run the `forge:area-note`
skill once per directory the domain owns, passing it that directory. The note reaches the agent by
itself the first time it reads a file there. What is too short for its own note goes in the agent's body.

## 4. Report

The file, the domain, the one-line description. Nothing else.

`/forge:issue` selects the agent per increment with `agent: "project:<domain>"`. Nothing in an issue
names one.
