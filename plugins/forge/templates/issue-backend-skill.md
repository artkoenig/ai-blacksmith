---
name: issue-backend
description: How this project stores issues. Use whenever an issue must be created, listed, read, or closed.
---

# Issue backend

Backend: <github | markdown files | jira | other>

Every command prints the smallest useful answer. Autonomous runs pay for every extra line.

## Create

<exact command. Prints the new issue id and nothing else.>

## List open

<exact command. One line per issue: "<id> <title>".>

## Read

<exact command taking an id. Prints the issue body verbatim, nothing else.>

## Update status

<exact command taking an id and a status.>

## Close

<exact command taking an id.>

## Format

Issues follow the forge template: Goal, Acceptance criteria (`AC1`, `AC2`, … each optionally with
`| verify: <command>`), Out of scope. Preserve it exactly when writing and reading - the run parses
the criteria out of it.
