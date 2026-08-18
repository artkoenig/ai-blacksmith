# memory

Auto memory is off - `autoMemoryEnabled: false` in `.claude/settings.json`, and no
`CLAUDE_CODE_REMOTE_MEMORY_DIR`. Nothing is written by the session or by a subagent.

- Knowledge that must survive a session goes in `.claude/rules/*.md`, committed. That is the only
  persistent channel.
- The `memory: project` field on an agent does nothing while auto memory is off. The agent starts
  without the memory instructions and without the memory tool, and relearns the project each run.
- `.claude/agent-memory/implementer/MEMORY.md` is still tracked but reaches no agent.
