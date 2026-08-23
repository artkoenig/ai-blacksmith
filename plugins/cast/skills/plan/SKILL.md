---
name: plan
description: Draft a refactoring as a cast plan and judge it on the simulation - what moving, merging, inverting or splitting modules would do to the cycles, the layer metrics and the rule violations. Use before editing any file for a restructuring.
argument-hint: "[the refactoring goal - optionally followed by the target directory]"
allowed-tools: Bash, Read, Write
---

# A refactoring, drafted and simulated

The argument is the goal: what the restructuring is for, in the caller's words - optionally
followed by the directory to work on. A trailing word that names an existing directory is that
root; without one the working directory is the project.

The plan is yours to write. Nobody hands you one, there is no file to ask for, and a goal like
"break the cycle between ui and data" is the whole input this skill needs.

!`CAST="$(command -v cast || echo "${CLAUDE_PLUGIN_ROOT:-plugins/cast}/bin/cast")"; A="$ARGUMENTS"; R=.; L="${A##* }"; if [ -n "$L" ] && [ -d "$L" ]; then R="$L"; fi; echo "cast root: $R"; "$CAST" scan --root "$R" >/dev/null && "$CAST" report --root "$R"; ls "$R/.cast/plans" 2>/dev/null || echo "no plan written yet"`

That is the graph the plan is drafted against, freshly scanned, and any plan already written down.
`cast root:` is the root; every call below passes it as `--root <root>`.

## The loop

Draft, simulate, judge, redraft. Go round it until a simulation is accepted, or until you can say
which goal the graph will not give up.

1. **Draft.** Write `<root>/.cast/plans/<name>.json` yourself, `<name>` after the goal
   (`break-ui-data`). It is an object with an `operations` array, ordered - each operation applies
   to the graph the one before it left behind, so a module a `move` renamed is named by its new id
   from there on. The operations are `{"op":"move","module":"<id>","to":"<id>"}`,
   `{"op":"merge","modules":["<id>",...],"into":"<id>"}`,
   `{"op":"invert","from":"<id>","to":"<id>"}` and
   `{"op":"split","module":"<id>","into":[{"id":"<id>","imports":[],"importedBy":[]},...]}`.
   Every id is a module the report above named, spelled exactly.
2. **Simulate.** `cast plan simulate <name> --root <root>`. It writes nothing - no source file, no
   `.cast/graph.json`. Exit 2 is a plan that could not be applied at all: an unknown operation, or
   a module it names that the graph does not have. That is never a partial answer, so do not read
   the numbers off a run that died - fix the draft and simulate again.
3. **Judge.** Against the criteria below, on the report and on nothing else.
4. **Redraft.** A rejected plan is edited and simulated again. Say what you changed and why before
   you write it.

Every number comes twice, before and after:

- modules and edges, then `cycles` - a cycle the plan breaks is named.
- fan-in, fan-out and instability per layer, `I = fan-out / (fan-in + fan-out)`, counting only the
  edges that cross a layer boundary.
- `violations`, the rules of `<root>/.cast/rules.json` evaluated against both graphs, with the
  sites under each rule. The baseline is deliberately not applied: a plan is judged against every
  violation there is, not against the debt that was forgiven.

## What accepts a simulation

All four, in one report:

- it exited 0.
- `cycles` after holds no cycle before does not, and the goal's cycle is gone. A plan that trades
  one cycle for another has moved the problem.
- `violations` after names no rule site before does not, and at least one site is gone where the
  goal was a violation.
- the layer whose instability the goal is about moved toward it, and no other layer's instability
  moved the wrong way by more than the one that improved.

## What rejects it

- exit 2, or a plan the simulator could not apply. There is no number to read.
- any cycle, any violation, any unresolved import the current graph does not already carry. A
  refactoring that adds one is not an improvement with a cost, it is a regression.
- every number unchanged. The plan buys nothing and is not worth the edit.
- an operation nothing in the goal asked for. Drop it and simulate again; a plan is judged whole,
  so one gratuitous move fails the whole plan.

## Edit nothing until it is accepted

No source file is touched while this loop runs - not a rename, not an import, not one line ahead of
the plan. The plan file under `<root>/.cast/plans/` is the only thing written. Where a simulation
is accepted, report it and stop: the edits are the next piece of work, and they follow the accepted
operations in order.

## The picture

- `cast render --mermaid --plan <name> --root <root>` draws the graph the plan would leave, not the
  scanned one. That is the picture a refactoring issue carries - paste it into the issue.
- `cast render --html <file> --fragment --plan <name> --root <root>` is the same graph as a page,
  for a manual look at the plan; drop `--plan` for the current state, and publish both as Artifacts
  to compare. Without `--fragment` the page is a standalone file, sent with `SendUserFile`.

Both render, and neither writes a source file or `.cast/graph.json`; a plan that cannot be applied
exits 2 having drawn nothing.

Report what the plan improves and what it costs, in that order, and name a violation it adds.
