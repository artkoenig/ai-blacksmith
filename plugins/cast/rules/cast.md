# cast

The architecture is read from the graph, not from memory.

- Before answering what depends on what, where a cycle is, or how the code is layered, run cast:
  `/cast:map`. Before editing a single file for a restructuring, draft the move as a plan and judge
  it on the simulation: `/cast:plan`. Where the plugin is developed in place and its skills are
  symlinked, the two lose the prefix: `/map`, `/plan`.
- A dependency the project should forbid is priced by writing it down as a warning, not by a
  command of its own: `severity: "warn"` in `<root>/.cast/rules.json` lists every site `cast check`
  finds and leaves the exit code alone. Read the count, then switch the rule to `error`, hold the
  sites in `.cast/baseline.json` and switch, or drop the rule.
- The graph is read in a subagent, not in the session that asked. `cast:graph-analyst` answers what
  depends on what, where a cycle is, how the code is layered, what a layer edge is made of;
  `cast:refactor-planner` runs the draft-simulate-judge loop and edits no file. Each returns a few
  sentences and a path - the report, the edge listings and the rounds of simulation stay in the
  agent. Where the plugin is developed in place they lose the prefix too: `graph-analyst`,
  `refactor-planner`. Hand each one the session's scratch directory in its task - everything they
  write goes there, never into the checkout - and they publish their own page and return its link,
  so the markup is never handled in the session that asked. Run `/map` or `/plan` inline only where
  one look answers it.
- Name the directory in the task wherever the question is about one part of the tree - `src`, one
  package. An agent given none reads the whole project, and an answer about the whole project where
  one directory was asked about is the wrong answer. The same directory is the `--root` of every
  call: `/map src`, or `graph-analyst` told the question is about `src`.
- `cast scan` writes the graph outside the checkout - a scratch directory under the system temp,
  keyed by the root, printed by the scan - so no run leaves a file in the tree and no project has
  to gitignore one. `CAST_GRAPH` names the file where a caller wants it somewhere else; exported
  once, the scan and the command reading its graph agree.
- Every call resolves the binary the way the skills do - `command -v cast`, else
  `${CLAUDE_PLUGIN_ROOT}/bin/cast` - and passes the same `--root`.
- A refactoring is judged on the simulation before it is executed: `cast plan simulate <name>`
  writes no source file and no graph file, and reports the cycles, the layer metrics and the
  rule violations before and after (`${CLAUDE_PLUGIN_ROOT}/README.md:176-180`).
- What the user looks at in the session is the page, and in a conversation it is the answer
  rather than an extra offered on request: `cast render --html <file> --fragment
  --root <root>`, and `--plan <name>` for the graph a refactoring would leave. Publish that file as
  an Artifact and hand over the link. `--fragment` is what makes it publishable: no document of its
  own for the host to reject, every colour a theme token the host sets
  (`${CLAUDE_PLUGIN_ROOT}/README.md:242-251`). The page is rendered, not authored - there is no
  design pass to make over it. Drop `--fragment` where the user wants the file itself and send that
  with `SendUserFile`. Never paste its markup either way. It fetches nothing, opens any node to any
  depth and names the rule behind every breaking edge
  (`${CLAUDE_PLUGIN_ROOT}/README.md:211-240`).
- What goes into an issue or a document is mermaid: `cast render --mermaid --root <root>`, in a
  fenced `mermaid` block. It draws one node per layer and labels each arrow with the module edges
  behind it (`${CLAUDE_PLUGIN_ROOT}/README.md:184-186`), so it stays readable where no browser
  opens it.
- Neither render is a claim of its own. A number in an answer comes from `cast report`,
  `cast edges` or a simulation, and says which.
