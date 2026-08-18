# forge

- `/forge:issue` writes issues and starts runs. Never implement an issue by hand.
- Checks run through `forge-test`, `forge-lint`, `forge-typecheck`, `forge-build`. Each answers `0`
  or `1`; escalate with `--failing`, then `--detail <id>`.
- Raw runners are rewritten or refused.
- Issue storage: `.claude/skills/issue-backend/SKILL.md`.
- Project knowledge: `.claude/rules/*.md`, committed, one topic per file.
