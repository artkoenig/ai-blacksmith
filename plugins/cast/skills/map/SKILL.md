---
name: map
description: Show the module graph of this project - the modules and edges, the imports that resolve to nothing, the dependency cycles, and the layers every module falls in. Use to answer what depends on what, where a cycle is, or how the code is layered.
argument-hint: "[no arguments]"
allowed-tools: Bash, Read
---

# The module graph

!`CAST="$(command -v cast || echo "${CLAUDE_PLUGIN_ROOT:-plugins/cast}/bin/cast")"; "$CAST" scan >/dev/null && "$CAST" report`

That is the graph as the code is right now - the scan ran first, so nothing above was read from a
`graph.json` written before the last edit.

Read it in this order, and report only what it actually says.

- `unresolved` imports first. Each one is an edge that landed nowhere: a typo, a missing alias in
  `tsconfig.json`, or a language this project's adapters do not cover. Name the files.
- `cycles` next. Every module of a cycle is listed, the whole strongly connected component, not
  the one the walk entered through. A cycle is the finding; do not rank it by module count.
- `layers` last, with `unassigned` beside them. `unassigned` is not a small layer, it is the
  modules `<root>/.cast/layers.json` claims for nothing - or the absence of that file, in which
  case the first directory level was the layer.

Follow one layer edge down with `cast edges --from <layer> --to <layer>`, which lists the module
edges behind it with the file and line of each import. Draw it with
`cast render --mermaid [--expand <layer>]` only when asked for a picture.

Answer in prose with the numbers from the report. Never restate a count the report did not give.
