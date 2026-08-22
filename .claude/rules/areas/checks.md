---
paths:
  - "test.sh"
---

# test.sh

- Every check that runs without a Claude Code session. `forge-test` wraps it: it counts the `ok`
  lines through `passingPattern` and reports the `FAIL` lines through `failingPattern`, so a suite
  that prints neither is invisible to both. The suites: the manifest and syntax, the wrapper
  contract against a fixture project, every hook decision, the startup measurement against a
  fixture agent and a synthetic transcript, that the project rules are tracked, that every area
  note parses and still globs something, and the workflow control flow against stubbed agents -
  wave order, stall detection, skipped dependents, merge conflicts, a missing issue id, and nine
  `cast *` suites over one scanned fixture project. The cast fixture ships its own
  `.cast/layers.json`, so every `cast report` assertion sees the layer sections too.
- The manifest and syntax suite loops `for d in plugins/*/`: validate, `node --check`, `bash -n`
  and the executable-bit checks are derived from the plugin directories, each guarded by
  `[ -f "$f" ] || continue` so a plugin shipping no `bin/`, `scripts/` or `workflows/` is skipped.
  It also checks that every `.claude-plugin/marketplace.json` entry mirrors its plugin's own
  `plugin.json` on `displayName`, `description` and `keywords`.
  Forge's `hooks/hooks.json` check stays named - forge is the only plugin that ships one. The
  suites below it stay forge-bound on purpose.
- A suite is a `# --- <name> ---` block that ends in `ok <name>` or `fail <name> "<what>"`.
  `fail` sets `FAILED`; the script exits with it.
- Guard a multi-step suite with `S=0` and report once at the end.
- Fixtures are `mktemp -d` projects carrying their own `.forge/config.json`. Never point a suite at
  the repository's own config.
- Hooks are exercised by piping JSON into the script; agents are never spawned.
- Keep the failure message specific enough to act on. `forge-test` shows it verbatim: the lines
  from the `FAIL` up to the next one are the whole report a caller gets.
- Every case names the break it catches, per `.claude/rules/tests.md`. Prove it: remove the line
  the case exists for, watch the suite go red, put it back.
- Each new `mktemp -d` fixture replaces the EXIT trap; the new trap must list every fixture dir so far, or the suite leaks one.
