---
paths:
  - "plugins/cast/**"
---

# cast

The module graph of a project, and the rules it must obey. `bin/cast` and `bin/cast-check` are
shims; all behaviour is `scripts/cast.js`, and every fact about a language is an adapter file.

- The engine holds no language knowledge, and that is the point of the plugin. Extensions,
  import patterns, edge kinds and resolution all come from an adapter. Anything language-specific
  added to `scripts/cast.js` breaks the `cast graph` suite, which drives a fixture adapter for a
  made-up `.toy` language through the engine.
- Adapters load from `adapters/*.js` and from `<root>/.cast/adapters/*.js`. A project adapter
  exports `{name, extensions, patterns, ignore?, init?, resolve}`; `init`'s return becomes
  `ctx.state` on every `resolve` call. `resolve` answers `{to}`, `{external: true}` or `null`.
- `null` is never a dropped edge. It is recorded with `resolution: "unresolved"` and named by
  `cast report`; an adapter that swallows a miss makes the report lie.
- Patterns are matched in order and one `(line, specifier)` makes one edge, first kind wins. That
  ordering is the whole type/value classification: `import type` matches the value pattern too, so
  a type pattern moved below a value one silently reclassifies every type edge.
- Pattern regexes must carry one capture group, the specifier, and tolerate newlines inside the
  statement (`[^;'"]*`, not `[^\n]*`) - multi-line imports are the common case in real code.
- The edge site is the line the statement starts on, taken as `m.index + m[0].search(/\S/)`, not
  the offset of the specifier. Patterns therefore open with a prefix class (`[\s;}]`, `[^\w.$]`)
  to avoid matching inside an identifier, and that prefix must not be part of the capture.
- `cast report` names whole strongly connected components, computed by an iterative Tarjan. Never
  make it recursive: a real project's graph is deeper than the node stack.
- Layers are read at report time from `<root>/.cast/layers.json`, never baked into `graph.json`, so
  re-layering a project needs no rescan. The file maps glob to layer name, first match wins, and
  the glob engine is `globToRe` in `scripts/cast.js`: `**` spans segments, `*`/`?` stay inside one.
  No `layers.json` means the first directory level is the layer (a root-level file lands in `.`).
- A module no glob claims is `unassigned`, the same contract as an unresolved edge: counted and
  named by `cast report`, never dropped, and never swept into a declared layer.
- `assign()` keys placement by module id, which is what makes "exactly one layer" true by
  construction; `cast edges --from <l> --to <l>` filters resolved module edges through that map.
- `cast render` reads the layers at render time like `report` does, and never rewrites the graph.
  Layer nodes are `L_<name>` and module nodes `M_<id>`, both sanitised to `[^A-Za-z0-9]->_`, with
  the real name only in the quoted label - a test matches the label, never the id alone.
- The default altitude is layers: a module node without `--expand <layer>` is the bug the
  `cast altitude` suite exists to catch. An edge whose two endpoints collapse to the same node is
  dropped, so a layer never gets a self loop; `--expand` moves one endpoint to the module.
- The layer arrow's `|n|` label is the count of module edges behind it, the same number
  `cast edges --from --to` lists - the two must not drift apart.
- `--html` is deliberately dependency-free: the page inlines the mermaid source as escaped text
  and loads nothing over the network, which the `cast html` suite asserts. Adding a CDN script
  turns it red.
- Exercised by the twenty `cast *` suites in `test.sh`, all reading one scanned fixture. Assert
  against the written `.cast/graph.json`, never an in-process call - the file is the contract.
- `.cast` is in `ALWAYS_IGNORED`, so a project's own adapters are loaded but never scanned as
  modules. Walking also skips every dot directory.
- The regex limit belongs in `README.md`, not in a workaround: inline `import { type X }` stays
  `value` on purpose.
- Separators and control characters in `scripts/cast.js` are written as escapes (`'\0'`), never as
  the raw byte: one literal NUL makes git and grep treat the file as binary, so the diff carries no
  hunks and `grep` prints `binary file matches` instead of lines.
- Rules are read at check time from `<root>/.cast/rules.json`, like layers.json and for the same
  reason: a rule can change with no rescan. `forbidden` names an edge that must not exist,
  `allowed` is the exception list, and an allowed rule matching the same edge drops the violation.
- A rule side is a layer name where `assign()` reports one (`unassigned` included), and a
  `globToRe` path glob otherwise. Layer wins on a tie, so a layer named like a directory is read
  as the layer - a rule between two files inside one layer must name the files.
- `cast check` evaluates every resolved module edge, never the layer aggregate `mermaid` builds:
  the render drops an edge whose endpoints collapse to one node, and the `cast check altitude`
  suite is what catches an evaluator rebuilt on top of it.
- The exit code comes from severity, not from the violation count: `warn` is listed and leaves 0.
  The summary is always the last line, and on a clean project the only line - that single line is
  the wrapper contract `bin/cast-check` inherits.
- `die()` is exit 2 throughout, which is what makes an unreadable or invalid `rules.json` the
  "could not run" answer of the wrapper contract rather than a violation or a pass. Validation
  belongs in `readRules` for that reason.
- An unknown rule attribute is reported as `not evaluated: <rule>: <key>`, never ignored. A new
  attribute means adding it to `RULE_KEYS` in the same change.
- One rule object is validated in exactly one place, `readRule`; `readRules` maps it over the file
  and `cast rules preview` calls it on the command-line rule, so a tried rule is read by the rules
  the written one is read by. `group()` is the shared rule/layer-edge/site rendering.
- `cast rules preview '<rule json>'` counts the module edges the rule would flag per edge and
  never per module - one module with three forbidden imports is three imports to move - and
  applies the project's `allowed` list so the number is what `cast check` would add today. It
  reports, so it exits 0 even on a rule it flags; only an unreadable rule is `die()`'s exit 2.
- `rules` is the only command with a subcommand and a positional. `main` takes `argv[1]`/`argv[2]`
  before the flag loop and starts the loop at 3; the loop knows flags only and `die(USAGE)`s on
  anything else, so a new positional command must do the same or it dies on its own argument.
- `bin/cast-check` scans before it checks, so a check command needs no arguments and never reads a
  stale graph. Every `bin/*` file must be executable, or the manifest suite fails on it.
- `.cast/baseline.json` holds inherited violations and is read at check time like the rules. A
  held violation drops out of the listing and out of the exit code, and is counted in the summary
  as `, N baselined` - a suffix, so the clean-project single line stays one line.
- A baseline entry is keyed by rule, file, imported module and edge kind, never by line: keying on
  the line churns the file on every edit above the import. `baselineKey` is that key, and both
  `check` and `cast baseline` must go through it.
- `cast baseline --update` refuses, with exit 1 and no write, a baseline holding more violations
  than the one it replaces - that refusal is the whole ratchet. No baseline yet is the bootstrap
  case and accepts any count. An update writes only the violations there are now, so a fixed one
  is dropped.
