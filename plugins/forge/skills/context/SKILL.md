---
name: context
description: Show what each agent loads into its context when it starts - measured start tokens, the breakdown by source, and the saved copies of what was loaded. Use to find out why an agent starts expensive.
allowed-tools: Bash, Read
---

# Startup context

!`FC=$(command -v forge-context || echo "${CLAUDE_PLUGIN_ROOT:-plugins/forge}/bin/forge-context"); "$FC"`

Two numbers per run, and they answer different questions.

- `start` is measured: the tokens the model actually saw on its first turn, read back from the
  transcript. It includes the system prompt and the tool schemas, which no project file explains.
- `est` is the sum of the files the start hook found: the agent definition, its `MEMORY.md` index,
  the skills it declares, the project rules. This is the part the project owns and can shrink.

Report a table grouped by agent: runs, median `start`, median `est`, trend across the most recent
runs. Then one line of interpretation.

- `est` rising run over run means a source file is growing. Almost always `MEMORY.md` past its
  200-line index, or a skill that turned into prose.
- `start` rising while `est` is flat is not the project's doing. Say so instead of hunting for it.
- `start` minus `est` is roughly fixed per agent. A jump means the agent gained tools or skills.

Escalate only when the table raises a question:

- `forge-context --sources <id>` - that run broken down by source, largest first, with the
  unattributed remainder named.
- `forge-context --dump <id>` - the copies saved under `.forge/context/<id>/`. Read one to see what
  the agent actually started with, not what the file says today.
- `forge-context --agent <name>` - one agent's runs only.

`start` is missing where the transcript did not name the agent's turns. Treat it as absent, not zero.

Report the table and one line of interpretation. Nothing else.
