---
paths:
  - "plugins/cast/**"
---

# cast

The module graph of a project, and the rules it must obey. `bin/cast` and `bin/cast-check` are
shims; all behaviour is `scripts/cast.js`, and every fact about a language is an adapter file.

- The engine holds no language knowledge, and that is the point of the plugin. Extensions, import
  patterns, edge kinds and resolution all come from an adapter. Anything language-specific added to
  `scripts/cast.js` breaks `cast graph`, which drives a fixture `.toy` adapter through the engine.
- Adapters load from `adapters/*.js` and `<root>/.cast/adapters/*.js`, exporting
  `{name, extensions, patterns, ignore?, init?, resolve}`; `init`'s return is `ctx.state` on every
  `resolve`, which answers `{to}`, `{external: true}` or `null`.
- `null` is never a dropped edge: it is `resolution: "unresolved"`, named by `cast report`. An
  adapter that swallows a miss makes the report lie.
- Patterns are matched in order and one `(line, specifier)` makes one edge, first kind wins. That
  ordering is the whole type/value classification: `import type` matches the value pattern too, so
  a type pattern moved below a value one silently reclassifies every type edge.
- Pattern regexes carry one capture group, the specifier, and tolerate newlines inside the
  statement (`[^;'"]*`, not `[^\n]*`). The site is the line the statement starts on
  (`m.index + m[0].search(/\S/)`), so the prefix class (`[\s;}]`) stays out of the capture.
- `cast report` names whole strongly connected components, by an iterative Tarjan - never
  recursive, a real graph is deeper than the node stack.
- Layers are read at report time from `<root>/.cast/layers.json`, never baked into `graph.json`:
  re-layering needs no rescan. Glob to layer name, first match wins, engine `globToRe` (`**` spans
  segments, `*`/`?` stay in one). No file means the first directory level is the layer, a fallback
  for `ENOENT` alone: a `layers.json` there but unreadable or invalid is exit 2, where one bare
  `catch` around read and parse would answer at an altitude nobody declared.
- A module no glob claims is `unassigned`: counted and named by `cast report`, never dropped and
  never swept into a declared layer.
- `assign()` keys placement by module id, making "exactly one layer" true by construction.
- `cast render` reads the layers at render time and never rewrites the graph. Layer nodes are
  `L_<name>`, module nodes `M_<id>`, every character mermaid rejects escaped to `_<hex>_`
  (`src/b.ts` -> `M_src_2f_b_2e_ts`), the name only in the quoted label - a test matches the label.
  Reversible on purpose: a bare `_` gives `src/a-b.ts` and `src/a_b.ts` one node (`cast node ids`).
- The default altitude is layers: a module node without `--expand <layer>` is the bug
  `cast altitude` catches. An edge whose endpoints collapse to one node is dropped, so a layer
  never self-loops; `--expand` moves one endpoint to the module.
- The layer arrow's `|n|` counts the module edges `cast edges --from --to` lists - never drift.
- `--html` is dependency-free on purpose: the page inlines the mermaid source as escaped text and
  loads nothing over the network, which the `cast html` suite asserts.
- Exercised by the `cast *` suites in `test.sh`, all reading one scanned fixture. Assert against
  the written `.cast/graph.json` - the file is the contract - unless the command writes no file.
- `.cast` is in `ALWAYS_IGNORED` - adapters are loaded, never scanned; walking skips dot dirs.
- The regex limit belongs in `README.md`, not a workaround: `import { type X }` stays `value`.
- Separators and control characters in `scripts/cast.js` are written as escapes (`'\0'`), never as
  the raw byte: one literal NUL makes git and grep treat the whole file as binary.
- Rules are read at check time from `<root>/.cast/rules.json`, like layers.json: a rule changes
  with no rescan. `forbidden` names an edge that must not exist, `allowed` drops it again.
- A rule side is a layer name where `assign()` reports one (`unassigned` included), a `globToRe`
  path glob otherwise; layer wins on a tie, so a rule inside one layer must name the files.
- `cast check` evaluates every resolved module edge, never the layer aggregate `mermaid` builds -
  the render drops intra-layer edges, and `cast check altitude` catches an evaluator built on it.
- The exit code comes from severity, not the violation count: `warn` is listed and leaves 0. The
  summary is the last line, and the only one on a clean project - the contract `bin/cast-check`
  inherits.
- `die()` is exit 2 throughout, which is what makes an unreadable or invalid `rules.json` the
  "could not run" answer rather than a violation or a pass; validation belongs in `readRules`.
  `soft(fn)` turns that exit into a throw for one call, used by `cast rules preview` alone:
  `writtenAllowed()` answers `{allowed: [], unreadable}`, so a command-line rule is still previewed
  beside a broken rules file, saying the allowed list was not applied.
- An unknown rule attribute is reported as `not evaluated: <rule>: <key>`, never ignored. A new
  attribute means adding it to `RULE_KEYS` in the same change.
- One rule object is validated in one place, `readRule`, which `readRules` maps over the file and
  `cast rules preview` calls on the command-line rule. `group()` is the shared
  rule/layer-edge/site rendering, reused by the plan report.
- `cast rules preview '<rule json>'` counts flagged module edges, never modules - three forbidden
  imports in one module are three imports to move - and applies the project's `allowed` list, so
  the number is what `cast check` would add. It reports: exit 0 even on a rule it flags.
- `rules` and `plan` take a subcommand and a positional: `main` reads `argv[1]`/`argv[2]` before
  the flag loop and starts it at 3. The loop knows flags only and `die(USAGE)`s on anything else,
  so a new positional command must do the same or it dies on its own argument.
- `bin/cast-check` scans before it checks, so a check command needs no arguments and never reads a
  stale graph. Every `bin/*` file must be executable, or the manifest suite fails on it.
- `.cast/baseline.json` holds inherited violations, read at check time like the rules. A held
  violation drops out of the listing and the exit code, and is counted as the summary suffix
  `, N baselined`, so the clean-project single line stays one line.
- A baseline entry is keyed by rule, file, imported module and edge kind, never by line, which
  would churn on every edit above the import. `baselineKey` is that key, for `check` and
  `cast baseline` alike.
- `cast baseline --update` refuses, exit 1 and no write, a baseline holding more violations than
  the one it replaces - that refusal is the ratchet. No baseline yet accepts any count. An update
  writes only the violations there are now.
- Plans are read at simulate time from `<root>/.cast/plans/<name>.json`, like the rules.
  `cast plan simulate` applies the ordered operations to a `JSON.parse(JSON.stringify)` copy and
  writes nothing at all - no source file, no `graph.json` - which is the whole command.
- Each operation is applied to the graph the one before it left behind, so a plan may name a module
  an earlier one created; `apply()` dies on a module it cannot find and `readPlan` on an unknown op
  or key, because a plan half-applied gives a flattering answer.
- The `cast plan readonly` suite cksums the whole fixture tree around the run and also asserts
  exit 0: a run that died changed nothing either, and would pass for the wrong reason.
- An edge's `file` is the id of the module holding it after the operation too: `move` and `merge`
  go through `resite()`, `split` sites each edge on its part, `invert` sites the new edge on the
  module that would declare it, at `line` 0. `cast plan sites` reads that graph in process.
- Plan metrics are at layer altitude and count only the edges that cross a layer boundary:
  `I = fan-out / (fan-in + fan-out)`, 0 when a layer has neither. The baseline is deliberately not
  applied to a simulation - a plan is judged against every violation there is.
