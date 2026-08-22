---
paths:
  - "plugins/cast/**"
---

# cast

The module graph of a project. `bin/cast` is a two-line shim; all behaviour is `scripts/cast.js`,
and every fact about a language is an adapter file.

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
- Exercised by the thirteen `cast *` suites in `test.sh`, all reading one scanned fixture. Assert
  against the written `.cast/graph.json`, never an in-process call - the file is the contract.
- `.cast` is in `ALWAYS_IGNORED`, so a project's own adapters are loaded but never scanned as
  modules. Walking also skips every dot directory.
- The regex limit belongs in `README.md`, not in a workaround: inline `import { type X }` stays
  `value` on purpose.
- Separators and control characters in `scripts/cast.js` are written as escapes (`'\0'`), never as
  the raw byte: one literal NUL makes git and grep treat the file as binary, so the diff carries no
  hunks and `grep` prints `binary file matches` instead of lines.
