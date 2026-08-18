---
paths:
  - "test.sh"
---

# test.sh

- Every check that runs without a Claude Code session. `forge-test` wraps it.
- A suite is a `# --- <name> ---` block that ends in `ok <name>` or `fail <name> "<what>"`.
  `fail` sets `FAILED`; the script exits with it.
- Guard a multi-step suite with `S=0` and report once at the end.
- Fixtures are `mktemp -d` projects carrying their own `.forge/config.json`. Never point a suite at
  the repository's own config.
- Hooks are exercised by piping JSON into the script; agents are never spawned.
- Keep the failure message specific enough to act on. It is the only thing `--detail` can show.
- Every case names the break it catches, per `.claude/rules/tests.md`. Prove it: remove the line
  the case exists for, watch the suite go red, put it back.
