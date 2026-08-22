---
paths:
  - "plugins/cast/**"
---

# cast

The module graph of a project, and the rules it must obey. `bin/cast` and `bin/cast-check` are
shims; all behaviour is `scripts/cast.js`, and every fact about a language is an adapter file.

- The engine holds no language knowledge: extensions, import patterns, edge kinds and resolution
  come from an adapter, and anything language-specific in `scripts/cast.js` breaks `cast graph`.
- Adapters load from `adapters/*.js` and `<root>/.cast/adapters/*.js`, exporting `{name, extensions,
  patterns, opaque?, ignore?, init?, resolve}`; `init`'s return is `ctx.state` on every `resolve`,
  which answers `{to}`, `{external: true}` or `null` - never a dropped edge, `resolution:
  "unresolved"`, named by `cast report`.
- An adapter's optional `opaque` patterns capture an import whose target is no literal string:
  `resolution: "opaque"`, `resolve` never called, counted and named by `cast report`. A second
  pattern list through `imports()`; the capture excludes a leading quote, or one line makes two.
- A count labelled `edges` is every import met - `cast report`'s line, with its resolution
  breakdown. Every narrower one says `module edges`: `cast edges`, `cast plan simulate`, the preview
  tail, the check summary, the page.
- Patterns match in order, one `(line, specifier)` makes one edge and the first kind wins - the
  whole type/value classification: `import type` matches the value pattern too, so a type pattern
  below a value one silently reclassifies every type edge. One capture group, the specifier,
  tolerating newlines inside the statement (`[^;'"]*`, not `[^\n]*`); the site is where the
  statement starts, `m.index + m[0].search(/\S/)`, so the prefix class stays out of the capture.
- Layers are read at report time from `<root>/.cast/layers.json`, never baked into `graph.json`:
  re-layering needs no rescan. Glob to layer name, first match wins, engine `globToRe` (`**` spans
  segments, `*`/`?` stay in one). No file means the first directory level is the layer - for
  `ENOENT` alone: unreadable, invalid or not a layer name is exit 2.
- A module no glob claims is `unassigned`: counted and named by `cast report`, never swept into a
  declared layer. `assign()` keys placement by module id, making "exactly one layer" structural.
- `cast render` reads the layers at render time and never rewrites the graph: layer nodes
  `L_<name>`, module nodes `M_<id>`, every character mermaid rejects escaped to `_<hex>_`
  (`M_src_2f_b_2e_ts`), the name only in the label - reversible, or `src/a-b.ts` and `src/a_b.ts`
  share one node. Mermaid's default altitude is layers: a module node without `--expand <layer>` is
  the bug `cast altitude` catches, and an edge collapsing to one node is dropped - no self-loop.
- One description, `viewData` (layers, module-edge sites, rule marks, the counts `report`/`check`
  print). Mermaid reads it at two altitudes through `viewAt(data, expand)`; the page reads it as a
  tree, `treeId` -> `treeOf` -> `viewTree(data, open)` -> `layoutTree`, with `marker`, `toggleOpen`
  and `groupIds` beside them. `html` inlines all seven and `draw` by `toString()`: each closes over
  nothing here and calls only the others, and one added goes in that list and in the exports too.
- The tree is layer / each folder level / file, keyed by containment path (`logic/src/b.ts`), every
  node carrying `modules`, its whole subtree. `viewTree` ends an arrow on the deepest *closed* node
  holding it and drops one inside a node, so the arrows leaving it sum to the imports leaving its
  subtree; `open` is ids, so any depth is nameable and `--expand` only seeds it, `hasChildren`
  survives the closing.
- `layoutTree` stacks vertically at every level, an open box `HEAD + PAD + Σ children + GAP*(k-1)`:
  as tall as what it shows, never as its subtree (`cast compact layout`). `M` returns as `metrics`.
- `M.TAP` (44) is the floor under `H`, `HEAD`, `LANE`, `CHAN`: `place` gives a node its header band
  `hx/hy/hw/hh` and an edge a `TAP` box by its label, only the header toggles - the ground of an
  open box answers no press - and transparent `hit`/`grab` shapes take what the drawn line is too
  thin for. `marker` is the glyph, on a node with children alone; `toggleOpen` deletes one id and
  nothing below it, so reopening shows what was open; `groupIds` is what open-all writes, close-all
  `[]`, both buttons reached by id. For a phone: the viewport meta, `#graph-scroll` around an svg
  keeping its own size, `overflow-x:hidden`, `touch-action`, never `svg{max-width:100%}`.
- `render` reads rules.json and baseline.json like `check`: severity colours and the rule labels an
  arrow, the baseline greys it `(inherited)`, live wins on a shared arrow, only a flagged one is
  styled. A mark sits on the module edge, so an intra-layer violation gets no arrow until the node
  holding both is opened. The page fetches nothing: its data a `<script>` with `<` escaped.
- `.cast` is in `ALWAYS_IGNORED` - adapters are loaded, never scanned; walking skips dot dirs.
- `README.md`'s `--html` paragraph is the page's prose spec: a change to what a press hits, or to
  what a node shows, leaves it false until that paragraph is edited in the same commit. No check
  greps it - the reviewer reads it.
- The regex limit belongs in `README.md`, not a workaround: `import { type X }` stays `value`.
- Separators and control characters in `scripts/cast.js` are escapes (`'\0'`), never the raw byte:
  one literal NUL makes git and grep treat the whole file as binary.
- Rules are read at check time from `<root>/.cast/rules.json`, like layers.json: a rule changes with
  no rescan. `forbidden` names an edge that must not exist, `allowed` drops it.
- A rule side is a layer name where `assign()` reports one (`unassigned` included), a `globToRe`
  path glob otherwise; layer wins a tie, so a rule inside one layer must name the files.
- `cast check` reads every resolved module edge, never mermaid's aggregate (`cast check altitude`).
- The exit code comes from severity, not the violation count: `warn` is listed and leaves 0. The
  summary is the last line, and the only one on a clean project - `bin/cast-check` inherits that.
- `die()` is exit 2 throughout: an unreadable or invalid `rules.json` is "could not run", not a
  violation or a pass, and validation belongs in `readRules`. `soft(fn)` turns it into a throw for
  `cast rules preview` alone, which previews beside a broken rules file and says so.
- An unknown rule attribute is `not evaluated: <rule>: <key>`, never ignored: a new attribute means
  adding it to `RULE_KEYS` in the same change.
- `readRule` validates one rule for `readRules` and `cast rules preview` alike; `group()` is the
  shared rule/edge/site rendering, reused by the plan report.
- `cast rules preview '<rule json>'` counts flagged module edges, never modules, and applies the
  project's `allowed` list: the number is what `cast check` would add. Exit 0 on a rule it flags.
- `bin/cast-check` scans before it checks: no arguments, never a stale graph, and every `bin/*` must
  be executable. `rules` and `plan` take a subcommand and a positional: `main` reads `argv[1]` and
  `argv[2]` before the flag loop, which starts at 3.
- `.cast/baseline.json` holds inherited violations, read at check time like the rules. A held one
  drops out of the listing and the exit code, counted as the summary suffix `, N baselined`.
- A baseline entry is keyed by rule, file, imported module and edge kind, never by line, which
  churns. `baselineKey`, for `check` and `cast baseline` alike.
- `cast baseline --update` refuses (exit 1, no write) a baseline holding more violations than the
  one it replaces - the ratchet; no baseline yet accepts any count.
- Plans are read at simulate time from `<root>/.cast/plans/<name>.json`, like the rules, and applied
  in order to a deep copy: `cast plan simulate` writes no source file and no `graph.json`. Each runs
  on the graph the one before left behind, so a plan may name a module an earlier one created;
  `apply()` dies on a module it cannot find, `readPlan` on an unknown op or key - half-applied
  flatters. `cast plan readonly` cksums the fixture around the run.
- An edge's `file` is the id of the module holding it after the operation too: `move`/`merge` go
  through `resite()`, `split` sites each edge on its part, `invert` the new edge at `line` 0.
- Plan metrics are at layer altitude and count only the edges crossing a layer boundary: `I =
  fan-out / (fan-in + fan-out)`, 0 when a layer has neither. The baseline is not applied - a plan is
  judged against every violation there is.
