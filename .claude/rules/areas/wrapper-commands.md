---
paths:
  - "plugins/forge/bin/**"
---

# Wrapper commands

- `forge-run` is the whole implementation. `forge-test`, `forge-lint`, `forge-typecheck` and
  `forge-build` are two-line shims that `exec` into it with their step name.
- The contract is the point: the default answer is `0` or `1`. Detail costs a second call
  (`--failing`, then `--detail <id>`). Never widen the default output.
- Config comes from `.forge/config.json`, per step: `command`, `parser`, `runArg`,
  `failingPattern`. An unconfigured step answers `unconfigured`, not an error.
- `failingPattern` is read by the `generic` parser only.
- On `PATH` only where the plugin is installed. Here they live at `plugins/forge/bin/`.
- Every file here must stay executable and pass `bash -n`; `test.sh` checks both.
- The wrapper suite in `test.sh` runs against a `mktemp -d` fixture carrying its own
  `.forge/config.json`. Extend that fixture rather than the repository config.
