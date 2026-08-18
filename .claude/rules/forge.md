# forge

This repository is the forge plugin, and it is developed with forge.

- `plugins/forge/` is the source. `.claude/skills`, `.claude/agents`, `.claude/workflows` and
  `.claude/output-styles` symlink into it, so edits are live in the session. Never edit through the
  symlink path.
- Checks run through `forge-test`. It answers `0` or `1`; escalate with `--failing`, then
  `--detail <id>`. It runs `test.sh`, which needs no Claude Code session.
- Used this way the components lose the `forge:` prefix: `/issue`, `/work`, `implementer`.
  Run the workflow with `agentPrefix: ""`.
- Issues live on GitHub. See `.claude/skills/issue-backend/SKILL.md`.
