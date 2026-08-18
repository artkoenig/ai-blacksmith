# forge

- Issues are written by `/forge:issue` and executed by `/forge:work <id>`. Never implement an issue
  by hand in the main conversation.
- Checks run through `forge-test`, `forge-lint`, `forge-typecheck`, `forge-build`. Each answers `0`
  or `1`. Escalate with `--failing`, then `--detail <id>`.
- Raw runners (`npm test`, `pytest`, `tsc`, `eslint`, …) are rewritten or refused.
- Issue storage is described in `.claude/skills/issue-backend/SKILL.md`.
- Agent knowledge lives in `.claude/agent-memory/<agent>/MEMORY.md` and is committed. Keep each
  index under 200 lines; only that much loads.
