# memory

- Subagent memory: `.claude/agent-memory/<agent>/MEMORY.md`, committed. Set by the agent's
  `memory: project` field.
- Main-session auto memory: `CLAUDE_CODE_REMOTE_MEMORY_DIR` in the `env` block of
  `.claude/settings.json` points at `.claude/agent-memory`, so it lands in the checkout and is
  committable instead of dying with the container. Claude Code appends `projects/<slug>/memory/`
  to that path itself.
- The path is absolute. The value takes no `${CLAUDE_PROJECT_DIR}` - that variable is not in the
  session environment - so a checkout at another path needs the value changed.
- `<slug>` encodes the checkout path, so a checkout elsewhere writes a different directory and
  reads none of what is committed here.
