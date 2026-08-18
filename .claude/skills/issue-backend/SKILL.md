---
name: issue-backend
description: How this project stores issues. Use whenever an issue must be created, listed, read, or closed.
---

# Issue backend

Backend: GitHub Issues on `artkoenig/test`, through the github MCP server. Where that server is not
connected, say so and stop - there is no fallback.

The `mcp__github__*` tools are deferred: they are not on a tool surface until `ToolSearch` loads
their schema. Before the first call, run `ToolSearch` with
`select:mcp__github__issue_read,mcp__github__issue_write,mcp__github__list_issues` - naming a tool
in an agent's `tools:` list does not surface it on its own.

## Create

`mcp__github__issue_write` with `method: "create"`, `owner: "artkoenig"`, `repo: "test"`, the title,
and the body. Report the issue number and nothing else.

## List open

`mcp__github__list_issues` with `state: "open"` and `minimal_output: true`. One line per issue:
`<number> <title>`.

## Read

`mcp__github__issue_read` with `method: "get"` and the issue number. Return the body verbatim.

## Update status / close

`mcp__github__issue_write` with `method: "update"`, the issue number, `state`, and `state_reason`.

## Format

Issues follow the forge template: Goal, Acceptance criteria (`AC1`, `AC2`, … each optionally with
`| verify: <command>`), Out of scope. Preserve it exactly - the run parses the criteria out of it.
