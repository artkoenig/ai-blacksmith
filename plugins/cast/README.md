# cast

The module graph of a project, and what is wrong with it.

```
cast scan [--root <dir>]     writes <root>/.cast/graph.json
cast report [--root <dir>]   reads it and says what is wrong
cast check [--root <dir>]    evaluates <root>/.cast/rules.json against the graph
cast rules preview <rule json> [--root <dir>]
                             one rule, tried before it is written down
cast plan simulate <name> [--root <dir>]
                             applies <root>/.cast/plans/<name>.json to a copy of
                             the graph and says what it would change
cast baseline [--update] [--root <dir>]
                             the inherited violations <root>/.cast/baseline.json
                             holds, and the ratchet that rewrites it
cast edges --from <layer> --to <layer> [--root <dir>]
                             the module edges behind one layer edge
cast render --mermaid [--expand <layer>] [--root <dir>]
cast render --html <file> [--expand <layer>] [--root <dir>]
                             the graph at layer altitude, one layer resolved
```

`scan` writes one entry per source module with its outgoing edges. Every edge carries the
specifier it came from, its kind (`value`, `type`, `dynamic`), the file and the line of the import
that produced it, and where it resolved to: another module, something outside the project,
nothing at all, or `opaque` - an import whose target is not a literal string, kept with the
expression as its target because nothing was looked up at all.

`report` counts the modules and the edges by kind and breaks them down by resolution, names every
import that resolved to nothing and every one it could not read, and names every module of every
dependency cycle - the whole strongly connected component, not the
module the walk entered it through. It also places every module in exactly one layer and sizes each
one.

## Layers

The altitude the graph is read at. `<root>/.cast/layers.json` maps globs to layer names:

```json
{ "src/ui/**": "ui", "src/**": "logic", "db/**": "data" }
```

First match wins, so the file's order is the priority. `**` spans whole path segments, `*` and `?`
stay inside one. A module no glob claims is `unassigned`: `cast report` counts it and names it,
never drops it. Without a `layers.json` the first directory level is the layer - enough to open a
view on any project, and no wizard. A value that is not a layer name stops the run, exit 2, like a
file that cannot be read: coerced, it would name a layer after the value and place modules in it.

`cast edges --from ui --to logic` lists the module edges behind that one layer edge, each with the
file and the line of the import that made it:

```
module edges ui -> logic 3
  src/ui/app.ts:1 -> src/logic/load.ts (value)
```

A count labelled `edges` is every import cast met - the one `cast report` prints. Every narrower
count says so: `module edges` is the resolved ones, in `cast edges`, `cast plan simulate`, the
preview and the check summary alike.

Only edges that landed on a module have a far layer; an unresolved or external import is named by
`cast report` instead.

## Rules

`<root>/.cast/rules.json` holds the dependencies the project does not allow. A `forbidden` rule
names an edge that must not exist; an `allowed` rule is the exception to it - an edge a forbidden
rule caught is dropped where an allowed rule claims the same edge.

```json
{
  "forbidden": [
    { "name": "ui-off-data", "severity": "error", "from": "ui", "to": "data",
      "kinds": ["value", "type", "dynamic"] }
  ],
  "allowed": [
    { "name": "the-one-legacy-read", "severity": "error", "from": "src/ui/report.ts",
      "to": "db/read.ts", "kinds": ["value"] }
  ]
}
```

`from` and `to` are a layer name where the project declares one, and a path glob otherwise (the
same glob engine `layers.json` uses), so a rule can be written between two layers or between two
files that share one. A side that is there but is not a string is rejected for its shape, naming
what was expected; only a missing one is reported as missing. `kinds` limits the rule to those edge kinds: a rule carrying
`kinds: ["value"]` is not violated by an `import type`. `severity` is `error` or `warn`; a warning
is listed and leaves the exit code alone. An attribute this evaluator does not know is reported as
`not evaluated`, never quietly passed.

`cast check` reads the rules against the module graph, never against the layer aggregate the
render draws, so a violation between two modules of one layer is found like any other. It answers
on the wrapper contract: exit 0 with a single line, exit 1 with every violation - grouped by rule
and by layer edge, each site with its file and its line - and exit 2 where the check could not run
at all. `bin/cast-check` is that check as a check command: it scans, then checks, and takes no
arguments.

A rule is tried before it is written down: `cast rules preview '<rule json>'` takes one rule
object - the same shape a `forbidden` entry has, read by the same validation - and reports the
module edges it would flag today, grouped like the check and counted per edge, never per module.
One module with three forbidden imports is three imports to move, so the count is 3 and the
modules are named beside it. The exceptions in the project's `allowed` list are applied, so the
number is what `cast check` would add. A preview reports and always exits 0; only a rule it cannot
read at all is exit 2.

## Baseline

`<root>/.cast/baseline.json` is the violations the project inherited. A listed violation is held:
it leaves `cast check` green and is counted in the summary as `N baselined`, so a rule can be
turned on before the code obeys it. A violation that is not listed is red like any other.

```json
{
  "violations": [
    { "rule": "ui-off-data", "file": "src/ui/report.ts", "to": "db/read.ts", "kind": "value" }
  ]
}
```

An entry is keyed by its rule, its file, the module imported and the edge kind - never the line,
which moves whenever anything above it is edited.

`cast baseline` says how big the debt is: how many violations are held, how many are not, and how
many held entries the code no longer violates. `cast baseline --update` rewrites the file from the
violations there are now - dropping the ones already fixed - and **refuses**, with exit 1, to write
a baseline holding more violations than the one it replaces. That refusal is the ratchet: the file
can only shrink, so a rule cannot quietly stop meaning anything.

## Plans

`<root>/.cast/plans/<name>.json` is a refactoring written down before anyone edits a file: an
ordered list of operations, applied by `cast plan simulate <name>` to a copy of the graph.

```json
{
  "operations": [
    { "op": "move", "module": "src/rel.ts", "to": "pkg/rel.ts" },
    { "op": "merge", "modules": ["src/b.ts", "src/c.ts"], "into": "src/bc.ts" },
    { "op": "invert", "from": "src/a.ts", "to": "src/bc.ts" },
    { "op": "split", "module": "src/multi.ts", "into": [
      { "id": "src/multi-core.ts", "imports": ["src/t.ts"], "importedBy": ["src/a.ts"] },
      { "id": "src/multi-shell.ts" } ] }
  ]
}
```

`move` renames a module and every edge that pointed at it - a module moved into another directory
lands in whatever layer the globs give its new path. `merge` folds several modules into one; an
edge between two of them stops being an edge. `invert` turns the edges between two modules around,
keeping their kind and their site. `split` breaks one module into parts: an outgoing edge lands on
the part whose `imports` names its target, an incoming one on the part whose `importedBy` names
its importer, and the first part takes everything no part claims.

The operations are ordered - each one is applied to the graph the one before it left behind, so an
operation may name a module an earlier one created. An operation kind, or an attribute, that cast
cannot apply is an error, never a silent skip.

The simulation writes nothing: no source file, no `.cast/graph.json`. It reports, before and
after, the modules and module edges, the cycles, the fan-in, fan-out and instability of every layer
(`I = fan-out / (fan-in + fan-out)`, counting only the edges that cross a layer boundary), and the
rule violations of `.cast/rules.json` - so a plan that removes a violation is visible as one that
does. The baseline is not applied: a plan is judged against every violation there is.

## Rendering

`cast render --mermaid` draws the graph at layer altitude: one node per layer, none per module,
and each layer arrow labelled with the number of module edges behind it - the same number
`cast edges` then lists. An edge inside one layer is no arrow at this altitude.

```
graph LR
  L_ui["ui (1)"]
  L_logic["logic (5)"]
  L_ui -->|3| L_logic
```

`--expand <layer>` resolves that one layer to its modules, in a subgraph, and leaves every other
layer a single node; an edge into it lands on the module, not on the layer.

An edge that breaks a rule in `.cast/rules.json` is drawn in the colour of its severity and
labelled with the rule name; one held by `.cast/baseline.json` is labelled `(inherited)` and drawn
in grey. The render reads both files at render time, exactly as `cast check` does.

`--html <file>` writes one self-contained page. The page draws the graph itself, in svg, from a
description embedded in the file, and fetches nothing at view time. Where the mermaid output knows
two altitudes, the page carries a containment tree over the whole project - the layer, then each
folder level, then the file - and any node with children opens at any depth. An open node keeps its
outline and stacks its children inside it, so a box is only ever as tall as what it shows. A node's
header is its control: pressing the header band across the top of a box opens it and closes it
again, while the ground of an open box, where the children sit, answers no press. Every arrow runs
between two closed nodes: opening a node splits its arrows over the children that carry the imports,
and the arrows leaving a node always sum to the imports leaving its subtree. An arrow ends in a head
on the module being imported, so which way the dependency runs is on the page rather than inferred,
and the head takes the arrow's own colour and state: a breaking edge points in its severity's
colour, one held by the baseline in the inherited grey. At rest the drawing carries boxes and
pointed lines and nothing else - no arrow is labelled with the count behind it. A number is asked
for: pointing at a node with a mouse, or pressing and holding it on a touch screen, keeps that
node's own arrows at full strength, fades every other arrow, and lists one line per neighbour saying
which way the dependency runs, how many module imports are behind it, which kinds it carries -
`2 value, 1 type`, what tells an edge a rule's `kinds` deliberately spares from one no rule names -
and the rule where one names it. Leaving the node, releasing the press, pressing elsewhere or
opening a group ends it. Clicking an arrow still lists
those imports, each with its file and its line. `--expand <layer>` opens that layer to begin with.
The counts beside the drawing are the ones `cast report` and `cast check` print for the same graph.

## Adapters

The engine holds no language knowledge. Which files are modules, which text is an import, what
kind of edge it makes and how a specifier resolves all come from an adapter file:

```js
module.exports = {
  name: 'javascript',
  extensions: ['.ts', '.js'],
  ignore: ['node_modules'],                       // directories never walked
  patterns: [{ kind: 'value', re: /.../g }],      // one capture group: the specifier
  opaque: [{ kind: 'value', re: /.../g }],        // optional; a target that is no literal string
  init(ctx),                                      // optional; its return is ctx.state
  resolve(spec, fromModuleId, ctx),               // {to} | {external: true} | null
}
```

`ctx` carries `root`, `exists(rel)`, `isFile(rel)`, `read(rel)` and the adapter's own `state`. A
`null` from `resolve` is an unresolved import: it is kept as an edge and named in the report, never
dropped. `opaque` patterns capture the expression of an import whose target is no literal string -
`require(path.join(dir, name))` - which is never resolved, and counted and named as `opaque` in the
report rather than passed over: a graph missing those edges must say so.

Adapters ship in `adapters/`. A project adds its own in `<root>/.cast/adapters/`, which is how a
second language arrives without touching the engine.

## What the javascript adapter does not do

It matches regexes, not an AST. That is deliberate - an AST parser per language is the cost the
adapter form exists to avoid - and it has one visible consequence:

- An inline type import, `import { type X } from './x'`, is classified `value`. Only the statement
  form, `import type { X } from './x'`, is classified `type`.

Aliases come from `tsconfig.json`: `compilerOptions.baseUrl` and `compilerOptions.paths`. An import
written through an alias resolves to the same node as the equivalent relative import. An alias that
matches a pattern but no file is unresolved, never an external package.
