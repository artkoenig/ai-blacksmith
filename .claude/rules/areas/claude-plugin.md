---
paths:
  - ".claude-plugin/**"
  - "plugins/*/.claude-plugin/**"
---

# claude-plugin

The two manifests a plugin ships: its own `plugins/<name>/.claude-plugin/plugin.json`, and its
entry in the repository-root `.claude-plugin/marketplace.json` that a user reads before installing.

- The root marketplace entry mirrors the plugin's own manifest: `displayName`, `description` and
  `keywords` must be byte-identical. Changing one alone fails the `manifest` suite in `test.sh`.
- Shipping behaviour in a plugin is a change to both manifests. The marketplace copy is the one
  that is easy to forget and the only one a user sees before install.
- No plugin pins a `version` on purpose - each is released from the tip of main, so the commit is
  the version. `claude plugin validate --strict` warns about exactly that and nothing else may
  print.
- `source` is the path to the plugin directory and has no counterpart in `plugin.json`; `name`
  keys the two files together, so a rename touches both plus the directory.
- `bash ./test.sh` (or `forge-test`) covers all of this in its first suite; it needs no session.
