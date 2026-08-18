---
name: issue-backend
description: How this project stores issues. Use whenever an issue must be created, listed, read, or closed.
---

# Issue backend

Backend: <github | markdown files | jira | other>

Every command below prints the smallest useful answer. Keep it that way: this skill is called from
autonomous runs where every extra line is paid for.

## Create

<exact command or tool call. Must print the new issue id and nothing else.>

## List open

<exact command. One line per issue: "<id> <title>".>

## Read

<exact command taking an id. Prints the issue body verbatim, nothing else.>

## Update status

<exact command taking an id and a status.>

## Close

<exact command taking an id.>

## Format

Issues follow the forge template: Goal, Acceptance criteria (AC1, AC2, …, each optionally with
`| verify: <command>`), Context (files, touch-only, agent), Out of scope. Preserve it exactly when
writing and reading, because the run parses the acceptance criteria out of it.
