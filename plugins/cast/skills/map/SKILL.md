---
name: map
description: Show the module graph of this project - the modules and edges, the imports that resolve to nothing, the dependency cycles, and the layers every module falls in. Use to answer what depends on what, where a cycle is, or how the code is layered.
argument-hint: "[optional target directory, default the working directory]"
allowed-tools: Bash, Read
---

# The module graph

The argument is the directory to read, and there is nothing else to pass. Without one the working
directory is the project.

!`CAST="$(command -v cast || echo "${CLAUDE_PLUGIN_ROOT:-plugins/cast}/bin/cast")"; R="$ARGUMENTS"; [ -n "$R" ] || R=.; echo "cast root: $R"; { "$CAST" scan --root "$R" >/dev/null && "$CAST" report --root "$R"; } 2>&1 || :`

That is the graph as the code is right now - the scan ran first, so nothing above was read from a
`graph.json` written before the last edit. `cast root:` is the root every further call needs:
pass it as `--root <root>` to each one, or you will answer about a different project.

Read it in this order, and report only what it actually says.

- `unresolved` imports first. Each one is an edge that landed nowhere: a typo, a missing alias in
  `tsconfig.json`, or a language this project's adapters do not cover. Name the files.
- `cycles` next. Every module of a cycle is listed, the whole strongly connected component, not
  the one the walk entered through. A cycle is the finding; do not rank it by module count.
- `layers` last, with `unassigned` beside them. `unassigned` is not a small layer, it is the
  modules `<root>/.cast/layers.json` claims for nothing - or the absence of that file, in which
  case the first directory level was the layer.

Follow one layer edge down with `cast edges --from <layer> --to <layer> --root <root>`, which lists
the module edges behind it with the file and line of each import.

In a conversation the page is the answer, not something held back until a picture is asked for.
Render it on every map:

- `cast render --html <file> --fragment --root <root>`, published as an Artifact, and hand the
  user the link. It opens any node to any depth and names the rule behind every breaking edge,
  which no paragraph does. Drop `--fragment` and send the file with `SendUserFile` where they
  want the file itself. Never paste its markup either way.
- `cast render --mermaid --root <root>` instead, in a fenced `mermaid` block, only where the
  answer is going somewhere no browser opens it - an issue, a document.

Beside the link, say in a few sentences what the report found: the unresolved imports, the cycles,
the layers. Never restate a count the report did not give.
