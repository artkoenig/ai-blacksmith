---
name: stats
description: Show tool calls per agent run from the forge metrics log. Use to check whether the token budget is holding.
allowed-tools: Bash, Read
---

# Run statistics

!`test -f .forge/metrics.jsonl && tail -n 40 .forge/metrics.jsonl || echo "no metrics yet"`

Group by `agent`. Report a table: runs, median tool calls, trend across the most recent runs.

Anything `/forge:work` spawned is grouped as `workflow-subagent`: the `Workflow` tool does not pass
the agent's own type to the hook, so the implementer and the reviewer share one row. Say so rather
than reading that row as the implementer's.

The number that matters is tool calls per implementer run over time. Rising means the agent is
searching more to reach the same place - say that, and name the likely cause.

`toolCalls` comes from a transcript written asynchronously. Treat it as a trend, not an audit.

`startTokens`, `promptTokens` and `peakTokens` are read from the same transcript. They answer what a
run cost to start and how far it grew - `/forge:context` breaks the start down by source.

Report the table and one line of interpretation. Nothing else.
