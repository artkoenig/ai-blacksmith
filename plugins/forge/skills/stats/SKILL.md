---
name: stats
description: Show tool calls per agent run from the forge metrics log. Use to check whether the token budget is holding.
allowed-tools: Bash, Read
---

# Run statistics

!`test -f .forge/metrics.jsonl && tail -n 40 .forge/metrics.jsonl || echo "no metrics yet"`

Group by `agent`. Report a table: runs, median tool calls, trend across the most recent runs.

The number that matters is tool calls per implementer run over time. It falls as
`.claude/agent-memory/implementer/MEMORY.md` fills in. Flat or rising means the memory is not being
consulted or not being written well - say that, and name the likely cause.

`toolCalls` comes from a transcript written asynchronously. Treat it as a trend, not an audit.

`startTokens`, `promptTokens` and `peakTokens` are read from the same transcript. They answer what a
run cost to start and how far it grew - `/forge:context` breaks the start down by source.

Report the table and one line of interpretation. Nothing else.
