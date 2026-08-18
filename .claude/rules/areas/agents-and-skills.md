---
paths:
  - "plugins/forge/agents/**"
  - "plugins/forge/skills/**"
---

# Agents and skills

- One directory per skill, `SKILL.md` inside it. Supporting files are addressed with
  `${CLAUDE_SKILL_DIR}`, which resolves both installed and project-scope.
- Agent front matter carries `tools:`, `maxTurns:` and `skills:`. There is no `memory:` field any
  more - auto memory is off, and `.claude/rules/` is the only channel into an agent.
- `skills:` lists both `forge:<name>` and `<name>`. A missing one is skipped with a warning, so
  the preload works installed and here.
- `user-invocable: false` keeps a skill out of the slash list. The agent protocol uses it.
- Both directories are watched, so an edit to `SKILL.md` or an agent page is live within seconds
  ([skills](https://code.claude.com/docs/en/skills#live-change-detection),
  [agents](https://code.claude.com/docs/en/sub-agents)). A brand new directory is not watched until
  the next session.
- Never edit through `.claude/agents/` or `.claude/skills/`. They are symlinks into this source.
- `mcp__*` tools are deferred. Naming one in `tools:` does not surface it - the agent needs
  `ToolSearch` too, and must load the schema with `select:<name>` before the first call.
- A `tools:` edit is not live the way the body is: agents spawned in the same session after the
  edit still showed the old surface. Only a new session was not tried - assume one is needed.
