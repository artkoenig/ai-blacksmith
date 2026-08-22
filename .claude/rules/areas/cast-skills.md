---
paths:
  - "plugins/cast/skills/**"
---

# cast skills

The three ways a session reaches cast: `map`, `rules`, `plan`. They are prompts, not documentation
- each runs its wrapper with a `!` line, so the model reads an answer instead of a command it has
to compose. `cast check` deliberately has none: it answers through its exit code and needs no model.

- The `!` line resolves the binary itself:
  `CAST="$(command -v cast || echo "${CLAUDE_PLUGIN_ROOT:-plugins/cast}/bin/cast")"`. The fallback
  is what makes a skill work in this repository, where the plugin is not installed.
- Every one of them scans before it reads: `"$CAST" scan >/dev/null && "$CAST" <command>`. Layers,
  rules and plans are read at command time, but the graph is not - without the scan the answer is
  whatever the last scan left behind. Same reason `bin/cast-check` scans.
- `rules` and `plan` pass `"$ARGUMENTS"` straight into the wrapper, quoted: the rule is a JSON
  object with spaces and braces, and an unquoted expansion splits it into a usage error.
- Frontmatter is `name`, `description`, `argument-hint`, `allowed-tools` - `Bash, Read`. The
  `cast skills` suite in `test.sh` fails on a missing key and on a `name` that is not the directory.
- `.claude/skills/<name>` is a symlink into here, so an edit is live in the session; never edit
  through the symlink, and never copy instead of linking - the suite checks the link target.
- A new skill directory is not watched until the next session, unlike an edit to an existing one.
- The suite greps the `!` lines for the subcommand (`report`, `rules preview`, `plan simulate`), so
  a rewrite that keeps the prose and drops the execution goes red.
- `claude plugin validate ./plugins/cast --strict` is run by the manifest suite over every
  `plugins/*/`; no manifest lists the skills, they are discovered from `skills/`.
