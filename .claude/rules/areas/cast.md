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
  which answers `{to}`, `{external: true}` or `null` - never a dropped edge, but `unresolved`.
- An adapter's optional `opaque` patterns capture an import whose target is no literal string:
  `resolution: "opaque"`, `resolve` never called, named by `cast report`. A second pattern list
  through `imports()`; the capture excludes a leading quote.
- A count labelled `edges` is every import met - `cast report`'s line, with its resolution
  breakdown. Every narrower one says `module edges`: `cast edges`, the check summary, the page.
- Patterns match in order, one `(line, specifier)` makes one edge and the first kind wins - the
  whole type/value classification: `import type` matches the value pattern too, so a type pattern
  below a value one silently reclassifies every type edge. One capture group, the specifier,
  newlines tolerated (`[^;'"]*`); the site is `m.index + m[0].search(/\S/)`, the prefix out of the
  capture.
- Layers are read at report time from `<root>/.cast/layers.json`, never baked into `graph.json`:
  re-layering needs no rescan. Glob to layer name, first match wins, engine `globToRe` (`**` spans
  segments, `*`/`?` stay in one). No file means the first directory level is the layer - on `ENOENT`
  alone: unreadable, invalid or not a layer name is exit 2.
- A module no glob claims is `unassigned`: counted and named by `cast report`, never swept into a
  declared layer; `assign()` keys placement by module id.
- `cast render` reads the layers at render time and never rewrites the graph: layer nodes
  `L_<name>`, module nodes `M_<id>`, every character mermaid rejects escaped to `_<hex>_`
  (`M_src_2f_b_2e_ts`), the name only in the label - reversible, or `src/a-b.ts` and `src/a_b.ts`
  collide. Mermaid opens at layers (`cast altitude`); an edge collapsing to one node is dropped - no
  self-loop.
- One description, `viewData`: layers, module-edge sites, rule marks, the counts `report`/`check`
  print. Mermaid reads it at two altitudes via `viewAt(data, expand)`, the page as a tree: `treeId`
  -> `treeOf` -> `viewTree(data, open)` -> `layoutTree`, with `marker`, `toggleOpen`, `groupIds`;
  `html` inlines all seven and `draw` by `toString()`, each closing over nothing here.
- The tree is layer / folder level / file, keyed by containment path (`logic/src/b.ts`), each node
  carrying `modules`, its whole subtree. `viewTree` ends an arrow on the deepest *closed* node
  holding it and drops one inside a node; `open` is ids, `--expand` seeds it.
- `layoutTree` stacks vertically at every level, an open box `HEAD + PAD + Σ children + GAP*(k-1)`:
  as tall as what it shows, never as its subtree (`cast compact layout`). `M` returns as `metrics`.
- `M.TAP` (44) floors `H`, `HEAD`, `LANE`, `CHAN`: `place` gives a node a header band `hx/hy/hw/hh`,
  and only that band toggles - the ground of an open box answers no press. Transparent `hit`/`grab`
  shapes widen what is too thin to press; `marker` is the glyph, on a node with children alone;
  `toggleOpen` deletes one id and nothing below it, so reopening restores it. Phone: viewport meta,
  a self-sized svg in `#graph-scroll`, `overflow-x:hidden`, no `svg{max-width:100%}`.
- An arrow's label is a `TAP`-floored box beside its lane, never on it (`bx = mx + PAD`), pushed
  below any box already placed; it is both the press target (`hx/hy/hw/hh`) and an opaque backing
  (`.weight-bg`), and `height` counts label bottoms or a pushed one leaves the viewBox. `draw`
  passes over `l.edges` twice, curves then labels, or the next curve crosses the label before it.
- Direction is a `<defs>` marker per colour and state, `arrow-<state>-<colour>`: `viewTree` sets
  `marker` beside `kindCounts`/`kinds`/`kindLabel`, `layoutTree` dedupes heads into `markers`, and
  the kinds under the count separate an edge a rule's `kinds` spares from one no rule names.
- `test.sh` greps the page source with `grep -F` on substrings: `"g.addEventListener('click'"` hits
  any local ending in `g` (`bg`), failing a suite unrelated to the change. Name around it.
- `render` reads rules.json and baseline.json like `check`: severity colours and the rule label an
  arrow, the baseline greys it `(inherited)`, live wins on a shared arrow, only a flagged one is
  styled. A mark sits on the module edge, so an intra-layer violation gets no arrow until the node
  holding both is opened. The page fetches nothing: data in a `<script>`, `<` escaped, no asset.
- `README.md`'s `--html` paragraph is the page's prose spec: a change to what a press hits, or to
  what an arrow or a node shows, leaves it false until that paragraph is edited in the same commit.
- Control characters in `scripts/cast.js` are escapes (`'\0'`): a literal NUL reads as binary.
- Rules are read at check time from `<root>/.cast/rules.json`, like layers.json: no rescan.
  `forbidden` names an edge that must not exist, `allowed` drops it.
- A rule side is a layer name where `assign()` reports one (`unassigned` included), a `globToRe`
  glob otherwise; layer wins a tie, so a rule inside one layer must name the files.
- `cast check` reads every resolved module edge, never mermaid's aggregate (`cast check altitude`).
- The exit code comes from severity, not the count: `warn` is listed and leaves 0. The summary is
  the last line, the only one on a clean project.
- `die()` is exit 2 throughout: an unreadable or invalid `rules.json` is "could not run", not a
  violation or a pass, and validation belongs in `readRules`. `soft(fn)` turns it into a throw for
  `cast rules preview` alone.
- An unknown rule attribute is `not evaluated: <rule>: <key>`, never ignored: a new attribute means
  adding it to `RULE_KEYS` in the same change.
- `readRule` validates one rule for both readers; `group()` is the shared rule/edge/site rendering,
  reused by the plan report. `cast rules preview '<rule json>'` counts flagged module edges, never
  modules, and applies the project's `allowed` list: the number is what `cast check` would add. Exit
  0 on a rule it flags.
- `bin/cast-check` scans before it checks: no arguments, never a stale graph, and every `bin/*` must
  be executable. `rules` and `plan` take a subcommand and a positional: `main` reads `argv[1]` and
  `argv[2]` before the flag loop, which starts at 3. `.cast` is in `ALWAYS_IGNORED` - adapters are
  loaded, never scanned; walking skips dot dirs.
- `.cast/baseline.json` holds inherited violations, read at check time like the rules. A held one
  drops out of the listing and the exit code, counted as the summary suffix `, N baselined`. An
  entry is keyed by rule, file, imported module and edge kind, never by line, which churns
  (`baselineKey`, for `check` and `cast baseline` alike).
- `cast baseline --update` refuses (exit 1, no write) a baseline holding more violations than the
  one it replaces - the ratchet; no baseline yet accepts any count.
- Plans are read at simulate time from `<root>/.cast/plans/<name>.json`, like the rules, and applied
  in order to a deep copy: `cast plan simulate` writes no source file and no `graph.json`. Each runs
  on the graph the one before left behind, so one may name a module an earlier one created;
  `apply()` dies on a module it cannot find, `readPlan` on an unknown op or key.
- An edge's `file` is the id of the module holding it after the operation too: `move`/`merge` go
  through `resite()`, `split` sites each edge on its part, `invert` the new edge at `line` 0.
- Plan metrics are at layer altitude and count only the edges crossing a layer boundary: `I =
  fan-out / (fan-in + fan-out)`, 0 when a layer has neither. The baseline is not applied.
