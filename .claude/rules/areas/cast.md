---
paths:
  - "plugins/cast/**"
---

# cast

The module graph of a project, and the rules it must obey. `bin/cast` and `bin/cast-check` are
shims; all behaviour is `scripts/cast.js`, and every fact about a language is an adapter file.

- The engine holds no language knowledge: extensions, import patterns, edge kinds and resolution
  come from an adapter. Anything language-specific in `scripts/cast.js` breaks `cast graph`, which
  drives a fixture `.toy` adapter through the engine.
- Adapters load from `adapters/*.js` and `<root>/.cast/adapters/*.js`, exporting
  `{name, extensions, patterns, opaque?, ignore?, init?, resolve}`; `init`'s return is `ctx.state`
  on every `resolve`, which answers `{to}`, `{external: true}` or `null`.
- `null` is never a dropped edge: `resolution: "unresolved"`, named by `cast report`.
- An adapter's optional `opaque` patterns capture the expression of an import whose target is no
  literal string: `resolution: "opaque"`, `resolve` never called, counted and named by `cast
  report`. A second pattern list through `imports()`, so an adapter declaring none is untouched;
  the capture excludes a leading quote, or a literal specifier makes two edges on one line.
- A count labelled `edges` is every import met - `cast report`'s line, with a resolution breakdown
  under it. Every narrower count says `module edges`: `cast edges`, `cast plan simulate`, the
  preview tail, the check summary, the page. Relabelling one makes two lines of a run disagree.
- Patterns are matched in order and one `(line, specifier)` makes one edge, first kind wins - the
  whole type/value classification: `import type` matches the value pattern too, so a type pattern
  moved below a value one silently reclassifies every type edge.
- Pattern regexes carry one capture group, the specifier, and tolerate newlines inside the
  statement (`[^;'"]*`, not `[^\n]*`). The site is where the statement starts,
  `m.index + m[0].search(/\S/)`, so the prefix class stays out of the capture.
- `cast report` names whole SCCs, by an iterative Tarjan - a real graph outgrows the node stack.
- Layers are read at report time from `<root>/.cast/layers.json`, never baked into `graph.json`:
  re-layering needs no rescan. Glob to layer name, first match wins, engine `globToRe` (`**` spans
  segments, `*`/`?` stay in one). No file means the first directory level is the layer, a fallback
  for `ENOENT` alone: unreadable, invalid, or a value that is not a layer name is exit 2 - one
  bare `catch`, or `String(name)`, answers at an altitude nobody declared.
- A module no glob claims is `unassigned`: counted and named by `cast report`, never swept into a
  declared layer. `assign()` keys placement by module id, making "exactly one layer" structural.
- `cast render` reads the layers at render time and never rewrites the graph: layer nodes `L_<name>`,
  module nodes `M_<id>`, every character mermaid rejects escaped to `_<hex>_` (`M_src_2f_b_2e_ts`),
  the name only in the label - reversible, or `src/a-b.ts` and `src/a_b.ts` share one node.
- The default altitude is layers: a module node without `--expand <layer>` is the bug `cast altitude`
  catches. An edge collapsing to one node is dropped, so a layer never self-loops.
- The layer arrow's `|n|` counts the module edges `cast edges --from --to` lists - never drift.
- Every view draws from one description: `viewData` (layers, module-edge sites, rule marks, the
  counts `report`/`check` print) -> `viewAt(data, expand)` -> `layout`. `html` inlines the three by
  `toString()`, so they close over nothing here and the page cannot drift from `--expand`.
- `render` reads rules.json and baseline.json like `check`: severity colours and the rule labels an
  arrow, the baseline greys it `(inherited)`, live wins on a shared arrow, and only a flagged one is
  styled - a project with no rules renders what it always did. The page fetches nothing: its data in
  a `<script type="application/json">` with `<` escaped, and its own svg drawing code.
- Exercised by the `cast *` suites in `test.sh`, all reading one scanned fixture. Assert against
  the written `.cast/graph.json`, the contract, unless the command writes no file.
- `.cast` is in `ALWAYS_IGNORED` - adapters are loaded, never scanned; walking skips dot dirs.
- The regex limit belongs in `README.md`, not a workaround: `import { type X }` stays `value`.
- Separators and control characters in `scripts/cast.js` are escapes (`'\0'`), never the raw
  byte: one literal NUL makes git and grep treat the whole file as binary.
- Rules are read at check time from `<root>/.cast/rules.json`, like layers.json: a rule changes
  with no rescan. `forbidden` names an edge that must not exist, `allowed` drops it.
- A rule side is a layer name where `assign()` reports one (`unassigned` included), a `globToRe`
  path glob otherwise; layer wins a tie, so a rule inside one layer must name the files.
- `cast check` evaluates every resolved module edge, never the layer aggregate `mermaid` builds:
  the render drops intra-layer edges (`cast check altitude`).
- The exit code comes from severity, not the violation count: `warn` is listed and leaves 0. The
  summary is the last line, and the only one on a clean project - `bin/cast-check` inherits that.
- `die()` is exit 2 throughout: an unreadable or invalid `rules.json` is "could not run", not a
  violation or a pass, and validation belongs in `readRules`. `soft(fn)` turns that exit into a
  throw for `cast rules preview` alone, which previews beside a broken rules file and says so.
- An unknown rule attribute is `not evaluated: <rule>: <key>`, never ignored: a new attribute
  means adding it to `RULE_KEYS` in the same change.
- A side present but not a string is rejected by `sideShape` before `side()`, naming the shape
  expected; only an absent one is "carries no from" - one null for both calls a present key missing.
- One rule object is validated in one place, `readRule`, called by `readRules` and by `cast rules
  preview`. `group()` is the shared rule/layer-edge/site rendering, reused by the plan report.
- `cast rules preview '<rule json>'` counts flagged module edges, never modules - three forbidden
  imports in one module are three to move - and applies the project's `allowed` list: the number
  is what `cast check` would add. Exit 0 even on a rule it flags.
- `rules` and `plan` take a subcommand and a positional: `main` reads `argv[1]`/`argv[2]` before
  the flag loop, which starts at 3, knows flags only, and `die(USAGE)`s on anything else.
- `bin/cast-check` scans before it checks: no arguments, never a stale graph. Every `bin/*` file
  must be executable, or the manifest suite fails on it.
- `.cast/baseline.json` holds inherited violations, read at check time like the rules. A held one
  drops out of the listing and the exit code, counted as the summary suffix `, N baselined`.
- A baseline entry is keyed by rule, file, imported module and edge kind, never by line, which
  would churn on every edit above the import. `baselineKey`, for `check` and `cast baseline` alike.
- `cast baseline --update` refuses, exit 1 and no write, a baseline holding more violations than
  the one it replaces - the ratchet. No baseline yet accepts any count.
- Plans are read at simulate time from `<root>/.cast/plans/<name>.json`, like the rules, and
  applied in order to a deep copy: `cast plan simulate` writes no source file and no `graph.json`.
- Each operation is applied to the graph the one before left behind, so a plan may name a module
  an earlier one created; `apply()` dies on a module it cannot find, `readPlan` on an unknown op
  or key - a plan half-applied flatters.
- The `cast plan readonly` suite cksums the whole fixture tree around the run and asserts exit 0
  too: a run that died changed nothing either, and would pass for the wrong reason.
- An edge's `file` is the id of the module holding it after the operation too: `move`/`merge` go
  through `resite()`, `split` sites each edge on its part, `invert` sites the new edge on the
  module that would declare it, at `line` 0.
- Plan metrics are at layer altitude and count only the edges crossing a layer boundary:
  `I = fan-out / (fan-in + fan-out)`, 0 when a layer has neither. The baseline is not applied - a
  plan is judged against every violation there is.
