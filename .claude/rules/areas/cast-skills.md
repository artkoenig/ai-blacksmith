---
paths:
  - "plugins/cast/skills/**"
---

# cast skills

The two ways a session reaches cast: `map` and `plan`. They are prompts, not documentation
- each runs its wrapper with a `!` line, so the model reads an answer instead of a command it has
to compose. `cast check` deliberately has none: it answers through its exit code and needs no model.

- The `!` line resolves the binary itself:
  `CAST="$(command -v cast || echo "${CLAUDE_PLUGIN_ROOT:-plugins/cast}/bin/cast")"`. The fallback
  is what makes a skill work in this repository, where the plugin is not installed.
- Every one of them scans before it reads: `"$CAST" scan >/dev/null && "$CAST" <command>`. Layers,
  rules and plans are read at command time, but the graph is not - without the scan the answer is
  whatever the last scan left behind. Same reason `bin/cast-check` scans.
- Every skill takes an optional target directory and resolves it on the `!` line into `R`,
  defaulting to `.`; every call on that line carries `--root "$R"`, and the line echoes
  `cast root: $R` so the model passes the same root to the calls the body asks for. The
  `cast skill root` suite counts `"$CAST"` against `--root "$R"` on that line - they must match.
- `map`'s whole argument is the directory. `plan` carries a goal of its own, so the root is the
  trailing word and only where `[ -d "$L" ]`; the rest stays quoted as `"$A"`, since an unquoted
  expansion splits a goal with spaces into a usage error.
- `plan` drafts `<root>/.cast/plans/<name>.json` itself and loops draft -> simulate -> judge ->
  redraft, so it needs `Write` in `allowed-tools` and its `!` line reports the graph rather than
  simulating a plan that does not exist yet. `cast plan simulate` is run per loop from the body.
- The judgement is prose the `cast plan skill` suite greps by heading: `## What accepts a
  simulation`, `## What rejects it`, `## Edit nothing until it is accepted`. Renaming a heading
  fails the suite - the headings are the contract, not decoration.
- `render` is reached from the skills alone: the plan's `--mermaid --plan` is the picture an issue
  carries, `--html --plan` the manual look at the plan, `--html` in `map` the look at today.
- Frontmatter is `name`, `description`, `argument-hint`, `allowed-tools` - `Bash, Read`. The
  `cast skills` suite in `test.sh` fails on a missing key and on a `name` that is not the directory.
- `.claude/skills/<name>` is a symlink into here, so an edit is live in the session; never edit
  through the symlink, and never copy instead of linking - the suite checks the link target.
- A new skill directory is not watched until the next session, unlike an edit to an existing one.
- The suite greps the `!` lines for the command they run (`report`), so a rewrite that keeps the
  prose and drops the execution goes red.
- `claude plugin validate ./plugins/cast --strict` is run by the manifest suite over every
  `plugins/*/`; no manifest lists the skills, they are discovered from `skills/`.
