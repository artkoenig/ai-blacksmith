---
name: plan
description: Draft a refactoring as a cast plan and judge it on the simulation - what moving, merging, inverting or splitting modules would do to the cycles, the layer metrics and the rule violations. Use before editing any file for a restructuring.
argument-hint: "[the refactoring goal - optionally a plan to continue, optionally the target directory]"
allowed-tools: Bash, Read, Write
---

# A refactoring, drafted and simulated

The argument is the goal: what the restructuring is for, in the caller's words - optionally
followed by the directory to work on. A trailing word that names an existing directory is that
root; without one the working directory is the project.

The plan is yours to write. Nobody hands you one, there is no file to ask for, and a goal like
"break the cycle between ui and data" is the whole input this skill needs.

The one exception is a plan that already exists: a word in the argument that names one - a bare name
read under `<root>/.cast/plans/<name>.json`, or a path to a plan file anywhere - is a plan to
continue rather than a plan to draft. A path counts as a plan file only where it ends in `.json`
and holds an `operations` array; any other file the goal happens to name - a script to move, a
module to split - is a word of the goal and nothing more.

!`CAST="$(command -v cast || echo "${CLAUDE_PLUGIN_ROOT:-plugins/cast}/bin/cast")"; A="$ARGUMENTS"; R=.; L="${A##* }"; if [ -n "$L" ] && [ -d "$L" ]; then R="$L"; fi; P=""; for W in $A; do case "$W" in *.json) if [ -f "$W" ] && grep -q '"operations"' "$W"; then P="$W"; fi;; esac; if [ -f "$R/.cast/plans/$W.json" ]; then P="$W"; fi; done; echo "cast root: $R"; echo "cast plan: ${P:-none}"; "$CAST" scan --root "$R" >/dev/null && "$CAST" report --root "$R"; if [ -n "$P" ]; then echo "--- operations ---"; cat "$R/.cast/plans/$P.json" 2>/dev/null || cat "$P"; "$CAST" plan simulate "$P" --root "$R" || echo "that plan does not apply to this graph"; else ls "$R/.cast/plans" 2>/dev/null || echo "no plan written yet"; fi`

That is the graph the plan is drafted against, freshly scanned. `cast root:` is the root; every call
below passes it as `--root <root>`.

`cast plan: <name>` is a plan handed to you: its operations and its simulation against that graph
are printed above, and the loop starts from where it stands. `cast plan: none` is a plan to draft
from scratch - a word that names no plan is not a plan, even where it names an existing file, and
the listing under it is what the project already holds.

## The loop

Draft, simulate, judge, redraft. Go round it until a simulation is accepted, or until you can say
which goal the graph will not give up.

1. **Draft.** Write the plan yourself, `<name>` after the goal (`break-ui-data`). It goes in
   `<root>/.cast/plans/<name>.json` where it is worth keeping beside the code, and in a scratch
   directory where it is not - `cast plan simulate` takes a path as readily as a name. It is an object with an `operations` array, ordered - each operation applies
   to the graph the one before it left behind, so a module a `move` renamed is named by its new id
   from there on. The operations are `{"op":"move","module":"<id>","to":"<id>"}`,
   `{"op":"merge","modules":["<id>",...],"into":"<id>"}`,
   `{"op":"invert","from":"<id>","to":"<id>"}`,
   `{"op":"redirect","from":"<id>","to":"<id>","via":"<id>"}` - the edge `from -> to` rehung on the
   facade `via`, the repair for a boundary that exists but is bypassed - and
   `{"op":"split","module":"<id>","into":[{"id":"<id>","imports":[],"importedBy":[]},...]}`.
   Every id is a module the report above named, spelled exactly.
2. **Simulate.** `cast plan simulate <name> --root <root>`, or the path where the draft is not in
   `.cast/plans`. It writes nothing - no source file, no graph file. Exit 2 is a plan that could
   not be applied at all: an unknown operation, or a module it names that the graph does not have. That is never a partial answer, so do not read
   the numbers off a run that died - fix the draft and simulate again.
3. **Judge.** Against the criteria below, on the report and on nothing else.
4. **Redraft.** A rejected plan is edited and simulated again. Say what you changed and why before
   you write it.

## Continuing a plan you were handed

Where the preamble reported `cast plan: <name>`, that file is the plan. The loop is the same one;
only the start is different.

- The named file is the one you edit, in place. No copy under a new name, no second plan beside it -
  its history is git's.
- An operation you append applies to the graph the operations before it leave behind, not to the
  scanned one. A module an earlier `move` or `merge` renamed is named by its new id from there on,
  and the ids to spell are the ones the printed operations leave, read off the plan above.
- Simulate and judge the whole plan - the operations it arrived with and the ones you added -
  against the criteria below, never the addition alone. A plan is judged whole, so an operation that
  arrived with it is yours to defend or to drop.

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

Both render, and neither writes a source file or a graph file; a plan that cannot be applied
exits 2 having drawn nothing.

Report what the plan improves and what it costs, in that order, and name a violation it adds.
