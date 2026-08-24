---
paths:
  - "plugins/cast/**"
---

# cast

The module graph of a project, and the rules it must obey. `bin/cast` and `bin/cast-check` are
shims; all behaviour is `scripts/cast.js`, every fact about a language an adapter file.

- The engine holds no language knowledge: extensions, import patterns, edge kinds and resolution
  come from an adapter, and anything language-specific in `scripts/cast.js` breaks `cast graph`.
- Adapters load from `adapters/*.js` and `<root>/.cast/adapters/*.js`: `{name, extensions, patterns,
  opaque?, comments?, ignore?, init?, resolve}`; `init`'s return is `ctx.state` on every `resolve`,
  which answers `{to}`, `{external: true}` or `null` - never a dropped edge, but `unresolved`.
  `opaque` patterns capture an import whose target is no literal string: `resolution: "opaque"`,
  `resolve` never called, named by `cast report`; a second list through `imports()`, capture past
  the quote.
- `comments` (`{line, block, strings, regex}`) drives `mask()`: comments blanked before the
  patterns run, offsets and newlines kept so no line moves; a string (`{open, close, escape?,
  interpolate?}`) is only skipped - the specifier lives in one - and `interpolate` reads a template
  hole as code. `regex` (plus `class?`, `notAfter`) is a delimiter that is also an operator: without
  it a quote in `/[^'"]/` opens a string that never closes and every comment after it stands. It is
  blanked in one span, opened where `notAfter` misses the last code character (`last()` reads the
  blanked `out`) and `span()` closes on the line. No `comments` is raw text.
- A count labelled `edges` is every import met - `cast report`'s line, with its resolution
  breakdown. Every narrower one says `module edges`: `cast edges`, the check summary, the page.
- Patterns match in order, one `(line, specifier)` makes one edge and the first kind wins - the
  whole type/value classification: `import type` matches the value pattern too, so a type pattern
  below a value one silently reclassifies every type edge. One capture group, the specifier,
  newlines tolerated (`[^;'"]*`); the site is `m.index + m[0].search(/\S/)`, prefix out of capture.
- Layers are read at report time from `<root>/.cast/layers.json`, never baked into `graph.json`:
  re-layering needs no rescan. Glob to layer name, first match wins, engine `globToRe` (`**` spans
  segments, `*`/`?` stay in one). No file means the first directory level is the layer, on `ENOENT`
  alone: unreadable, invalid or not a layer name is exit 2. A module no glob claims is `unassigned`:
  counted and named by `cast report`, never swept into a layer; `assign()` keys it by module id.
- `cast render` reads the layers at render time and never rewrites the graph: layer nodes
  `L_<name>`, module nodes `M_<id>`, every character mermaid rejects escaped to `_<hex>_`
  (`M_src_2f_b_2e_ts`), name only in the label - reversible, or `src/a-b.ts` and `src/a_b.ts`
  collide. Mermaid opens at layers (`cast altitude`), an edge collapsing to one node is dropped.
- One description, `viewData`: layers, module-edge sites, rule marks, the counts `report`/`check`
  print. Mermaid reads it at two altitudes via `viewAt(data, expand)`, the page as a tree: `treeId`
  -> `treeOf` -> `viewTree(data, open)` -> `layoutTree`, with `marker`, `toggleOpen`, `groupIds`,
  `edgesAt`, `edgeLines`; `html` inlines them and `draw` by `toString()`, closing over nothing.
- The tree is layer / folder level / file, keyed by containment path (`logic/src/b.ts`), each node
  carrying `modules`, its whole subtree. `viewTree` ends an arrow on the deepest *closed* node
  holding it, drops one inside a node; `open` is ids, `--expand` seeds it.
- `layoutTree` stacks vertically at every level, an open box `HEAD + PAD + Σ children + GAP*(k-1)`:
  as tall as what it shows, never as its subtree (`cast compact layout`); `M` returns as `metrics`.
  `M.TAP` (44) floors `H` and `HEAD`: `place` gives a node a header band `hx/hy/hw/hh` and only that
  band toggles - the ground of an open box answers no press. Transparent `hit`/`grab` shapes widen
  what is too thin to press; `marker` is the glyph, on a node with children alone; `toggleOpen`
  deletes one id and nothing below it. Phone: viewport meta, a self-sized svg in `#graph-scroll`,
  `overflow-x:hidden`, no `svg{max-width:100%}`.
- An arrow is a bare curve and a `TAP`-wide transparent grab: no head, no label, no backing, and
  `width`/`height` end at the furthest `mx` and the last box. `weight`, `label`, `kinds`,
  `kindCounts`, `kindLabel`, `rule`, `state` and `sites` stay on it as data. Direction is the side: `down` (`y2 >= y1`) anchors both ends right of their boxes, up
  left, `mx` one `M.CLEAR` (16) past the boxes the span crosses (`flat`, less the ends and any box
  holding both, overlapping by y) - flat between neighbours, no lane, the stack at `PAD + CLEAR`.
- `edgesAt(edges, id)` is every arrow touching a node, `edgeLines(edges, id)` the panel's lines -
  both pure, both tested in node. Highlighting only subtracts: `.edge.dim` outside the set. `pointerenter`/`pointerleave` are bound for `pointerType ===
  'mouse'` alone or a touch screen highlights on every tap; touch is a `HOLD` timer from
  `pointerdown`, cancelled by `SLOP`/release/cancel, its `click` eaten once by `suppress`.
- `render` reads rules.json and baseline.json like `check`: severity colours and the rule label an
  arrow, the baseline greys it `(inherited)`, live wins on a shared arrow, only a flagged one is
  styled. A mark sits on the module edge, so an intra-layer violation gets no arrow until the node
  holding both is opened. The page fetches nothing: data in a `<script>`, `<` escaped, no asset.
  `README.md`'s `--html` paragraph is its prose spec: a change to what a press hits or what an
  arrow or a node shows leaves it false until that paragraph is edited in the same commit.
- `graphFile(root)` is `os.tmpdir()/cast/<base>-<sha1>/`; every reader rederives it from `--root`.
- Rules are read at check time from `<root>/.cast/rules.json`, like layers.json: no rescan.
  `forbidden` names an edge that must not exist, `allowed` drops it; a side is a layer name where
  `assign()` reports one (`unassigned` included), a `globToRe` glob otherwise, layer winning a tie,
  so a rule inside one layer must name the files. An unknown attribute is `not evaluated: <rule>:
  <key>` - add it to `RULE_KEYS` in the same change; `group()` renders rule/edge/site everywhere.
- `cast check` reads every resolved module edge, never mermaid's aggregate. Severity sets the exit,
  not the count: of `SEVERITIES` (`error, warn, info, ignore`) only `error` moves it, `warn` lists
  and leaves 0, `ignore` is skipped in `violations()`; an unknown one, or an invalid `rules.json`,
  is `die()` exit 2 from `readRules`. The summary is the last line, the only one when clean.
- A rule names one subject: an edge, or a shape - `circular`, `orphan`, `couldNotResolve`
  (`SUBJECTS`, `readRule` sets `r.subject`), two in one rule is exit 2. On a shape `from`/`to` only
  filter (`fromSpec`/`toSpec` default `**`); an orphan takes no `to` and prints under an `(orphan)`
  header, an unresolved `to` globs specifier text, never a layer. `candidates(graph, of, subject)`
  carries the violation in `.v`; `hits()` takes one. Fixture: `CASTKIN`, never `CASTFIX`.
- `bin/cast-check` scans before it checks: no arguments, never a stale graph, every `bin/*`
  executable. `plan` takes a subcommand and a positional: `main` reads `argv[1]` and `argv[2]`
  before the flag loop, which starts at 3; a `--root` that is no directory is exit 2 there. `.cast`
  is in `ALWAYS_IGNORED` - adapters are loaded, never scanned; walking skips dot dirs.
- `.cast/baseline.json` holds inherited violations, read at check time like the rules: a held one
  drops out of the listing and the exit code, counted as the suffix `, N baselined`, keyed by rule,
  file, imported module and edge kind, never by line, which churns (`baselineKey`). `--update`
  refuses (exit 1, no write) a baseline bigger than the one it replaces - the ratchet.
- Plans are read at simulate time, ops applying in order to a deep copy, each on the graph the one
  before left; `apply()` dies on an unknown module, `readPlan` on an unknown op or key. An op
  resites its edges: `move`/`merge` via `resite()`, `split` per part, `invert` at `line` 0.
  `planFile()` takes a `/` or `.json` as a path against cwd, else a name under `.cast/plans/`.
- Plan metrics count edges crossing a layer boundary alone: `I = fan-out / (fan-in + fan-out)`, 0
  when a layer has neither. `cast render --plan` draws `simulateGraph(scan, readPlan(...))` before
  any write: an unapplicable plan exits 2 with no page, and layers, rules and baseline read against
  the simulated graph, not the scanned one.
