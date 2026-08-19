---
paths:
  - "plugins/forge/bin/**"
---

# Wrapper commands

- `forge-run` is the whole implementation. `forge-test`, `forge-lint`, `forge-typecheck` and
  `forge-build` are two-line shims that `exec` into it with their step name.
- Two answers, and no third: exit `0` with the single line `<n>/<n> tests succeeded`, or exit `1`
  with every failing test and its detail. Exit `2` is for a step that could not run at all -
  unconfigured, or an argument that is not `--run <pattern>`. Never add a mode; a caller that has
  to escalate pays a turn to learn what the first answer should have carried.
- Config comes from `.forge/config.json`, per step: `command`, `parser`, `runArg`,
  `failingPattern`, `passingPattern`. An unconfigured step says `unconfigured` on stderr and
  exits `2`.
- `failingPattern` and `passingPattern` are read by the `generic` parser only.
- The count is best effort, the verdict is not: where the log carries no count, a green run says
  `all tests succeeded` rather than inventing one. Never let a missing count change the exit code.
- On `PATH` only where the plugin is installed. Here they live at `plugins/forge/bin/`.
- Every file here must stay executable and pass `bash -n`; `test.sh` checks both.
- The wrapper suite in `test.sh` runs against a `mktemp -d` fixture carrying its own
  `.forge/config.json`. Extend that fixture rather than the repository config.
- `forge-cfg` dispatch: `root`/`path`/`exists`/`get` exit `0`; anything else (including no argument)
  prints the usage line to stderr and exits `2`. `get` on a missing key still exits `0`.
- `test.sh` runs under `pipefail`, so `cmd | grep -q` inherits a non-zero exit from `cmd`. Assert on
  a captured variable when the command under test is meant to fail.
- The exit code of the run decides, not the log: a run that exited `0` has no failures, whatever
  its output happens to match. Parsers run only for a failing run, and only on the log that run
  just wrote.
- A failure that names no test still shows the tail of the log. An empty exit `1` tells the caller
  nothing and costs a round.
