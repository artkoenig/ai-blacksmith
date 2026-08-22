---
name: plan
description: Simulate a refactoring against the module graph - what moving, merging, inverting or splitting modules would do to the cycles, the layer metrics and the rule violations. Use before editing any file for a restructuring.
argument-hint: "[plan name, the file <root>/.cast/plans/<name>.json]"
allowed-tools: Bash, Read
---

# A refactoring, simulated

The argument is the plan name: `<root>/.cast/plans/<name>.json`, an ordered list of `move`, `merge`,
`invert` and `split` operations. Without one, ask which plan; never simulate a plan you wrote in
your head.

!`CAST="$(command -v cast || echo "${CLAUDE_PLUGIN_ROOT:-plugins/cast}/bin/cast")"; "$CAST" scan >/dev/null && "$CAST" plan simulate "$ARGUMENTS"`

The simulation writes nothing - no source file, no `.cast/graph.json`. Exit 2 is a plan that could
not be applied at all: an unknown operation, or a module it names that the graph does not have.
That is never a partial answer, so do not read the numbers off a run that died.

Every number comes twice, before and after:

- modules and edges, then `cycles` - a cycle the plan breaks is named.
- fan-in, fan-out and instability per layer, `I = fan-out / (fan-in + fan-out)`, counting only the
  edges that cross a layer boundary.
- `violations`, the rules of `<root>/.cast/rules.json` evaluated against both graphs, with the
  sites under each rule. The baseline is deliberately not applied: a plan is judged against every
  violation there is, not against the debt that was forgiven.

Report what the plan improves and what it costs, in that order, and name a violation it adds.
Then say the operations are ordered - each applies to the graph the one before it left behind - so
a plan that reports badly is edited and simulated again before any file is touched.
