---
name: stats
description: Show tool calls per agent run from the forge metrics log. Use to check whether the token budget is holding.
allowed-tools: Bash, Read
---

# Run statistics

## Recent runs

!`test -f .forge/metrics.jsonl && tail -n 40 .forge/metrics.jsonl || echo "no metrics yet"`

## Read it

Group by `agent` and report, in a small table: number of runs, median tool calls, and the trend
across the most recent runs.

The number that matters is tool calls per implementer run **over time**. It should fall as
`.claude/agent-memory/implementer/MEMORY.md` fills in, because the agent stops rediscovering the
project. Flat or rising means the memory is not being consulted or not being written well - say so
directly and name the likely cause.

`toolCalls` is counted from the agent's transcript file, which is written asynchronously, so a
value can lag by a call or two. Treat it as a trend, not an audit.

Report the table and one line of interpretation. Nothing else.
