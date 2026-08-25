---
paths:
  - "plugins/forge/agents/**"
  - "plugins/forge/skills/**"
---

# Agents and skills

- One directory per skill, `SKILL.md` inside it. Supporting files are addressed with
  `${CLAUDE_SKILL_DIR}`, which resolves both installed and project-scope.
- Agent front matter carries `tools:` and `skills:`. There is no `memory:` field any
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
- `test.sh` asserts skill structure by grepping numbered headings (`^## [0-9]\+\. <name>$`) and
  comparing their line numbers. Inserting a step means renumbering every later heading, and a
  heading reworded without updating `test.sh` fails a suite that never mentions the wording.
- A skill's supporting file is behaviour too: `skills/issue/issue-template.md` is the issue's
  shape, and a section added there is dead unless `SKILL.md` says how to fill it and when to drop
  it. `test.sh` greps both files, so they change together.
- `skills/bootstrap/SKILL.md` orders its greenfield path as a numbered markdown *list*, not as
  headings; `test.sh`'s `base-branch` suite pins that order by comparing the line of the push step
  with the line of `^[0-9]\+\. \*\*The MVP issues`. Reordering or rewording those items fails it.
- Several suites grep a skill for an exact phrase, so a sentence that wraps between the two words
  being grepped fails a check the prose still satisfies. Keep such phrases on one line.
