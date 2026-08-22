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
- Exercised by the six `cast *` suites in `test.sh`, all reading one scanned fixture. Assert
  against the written `.cast/graph.json`, never an in-process call - the file is the contract.
- `.cast` is in `ALWAYS_IGNORED`, so a project's own adapters are loaded but never scanned as
  modules. Walking also skips every dot directory.
- The regex limit belongs in `README.md`, not in a workaround: inline `import { type X }` stays
  `value` on purpose.
- Separators and control characters in `scripts/cast.js` are written as escapes (`'\0'`), never as
  the raw byte: one literal NUL makes git and grep treat the file as binary, so the diff carries no
  hunks and `grep` prints `binary file matches` instead of lines.
