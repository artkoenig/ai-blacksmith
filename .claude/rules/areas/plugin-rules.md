---
paths:
  - "plugins/forge/rules/**"
---

# Plugin rules

- `rules/forge.md` is the one rules file. The `SessionStart` hook injects it and `agent-protocol`
  attaches it with `@`, so the session and every agent read the same lines. Never restate one of
  them in either reader.
- It arrives as context at session start, so an edit is **not** live. `/clear` to pick it up.
- The plugin ships no output style. Brevity is Claude Code's built-in **Concise**, selected by name
  through `outputStyle` in `.claude/settings.json`. A style shipped here would need
  `force-for-plugin` to apply and would override whatever the user picked.
- Everything a style cannot carry belongs here instead: an output style never reaches a subagent,
  this file does.
