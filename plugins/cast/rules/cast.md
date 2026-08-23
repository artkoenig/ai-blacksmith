# cast

The architecture is read from the graph, not from memory.

- Before answering what depends on what, where a cycle is, or how the code is layered, run cast:
  `/cast:map`. Before editing a single file for a restructuring, draft the move as a plan and judge
  it on the simulation: `/cast:plan`. A dependency the project should forbid is priced before it is
  written down: `/cast:rules`. Where the plugin is developed in place and its skills are symlinked,
  the three lose the prefix: `/map`, `/plan`, `/rules`.
- Every call resolves the binary the way the skills do - `command -v cast`, else
  `${CLAUDE_PLUGIN_ROOT}/bin/cast` - and passes the same `--root`.
- A refactoring is judged on the simulation before it is executed: `cast plan simulate <name>`
  writes no source file and no `.cast/graph.json`, and reports the cycles, the layer metrics and the
  rule violations before and after (`${CLAUDE_PLUGIN_ROOT}/README.md:161-165`).
- What the user looks at in the session is the page: `cast render --html <file> --root <root>`, and
  `--plan <name>` for the graph a refactoring would leave. It is one self-contained file that
  fetches nothing, opens any node to any depth and names the rule behind every breaking edge
  (`${CLAUDE_PLUGIN_ROOT}/README.md:196-214`). Send it with `SendUserFile`; never paste its markup.
- What goes into an issue or a document is mermaid: `cast render --mermaid --root <root>`, in a
  fenced `mermaid` block. It draws one node per layer and labels each arrow with the module edges
  behind it (`${CLAUDE_PLUGIN_ROOT}/README.md:169-171`), so it stays readable where no browser
  opens it.
- Neither render is a claim of its own. A number in an answer comes from `cast report`,
  `cast edges` or a simulation, and says which.
