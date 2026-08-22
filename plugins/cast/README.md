# cast

The module graph of a project, and what is wrong with it.

```
cast scan [--root <dir>]     writes <root>/.cast/graph.json
cast report [--root <dir>]   reads it and says what is wrong
cast edges --from <layer> --to <layer> [--root <dir>]
                             the module edges behind one layer edge
cast render --mermaid [--expand <layer>] [--root <dir>]
cast render --html <file> [--expand <layer>] [--root <dir>]
                             the graph at layer altitude, one layer resolved
```

`scan` writes one entry per source module with its outgoing edges. Every edge carries the
specifier it came from, its kind (`value`, `type`, `dynamic`), the file and the line of the import
that produced it, and where it resolved to: another module, something outside the project, or
nothing at all.

`report` counts the modules and the edges by kind, names every import that resolved to nothing,
and names every module of every dependency cycle - the whole strongly connected component, not the
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
view on any project, and no wizard.

`cast edges --from ui --to logic` lists the module edges behind that one layer edge, each with the
file and the line of the import that made it:

```
edges ui -> logic 3
  src/ui/app.ts:1 -> src/logic/load.ts (value)
```

Only edges that landed on a module have a far layer; an unresolved or external import is named by
`cast report` instead.

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
layer a single node; an edge into it lands on the module, not on the layer. `--html <file>` writes
the same view as one self-contained page - it carries the layer names and fetches nothing. How the
page looks is not a claim it makes.

## Adapters

The engine holds no language knowledge. Which files are modules, which text is an import, what
kind of edge it makes and how a specifier resolves all come from an adapter file:

```js
module.exports = {
  name: 'javascript',
  extensions: ['.ts', '.js'],
  ignore: ['node_modules'],                       // directories never walked
  patterns: [{ kind: 'value', re: /.../g }],      // one capture group: the specifier
  init(ctx),                                      // optional; its return is ctx.state
  resolve(spec, fromModuleId, ctx),               // {to} | {external: true} | null
}
```

`ctx` carries `root`, `exists(rel)`, `isFile(rel)`, `read(rel)` and the adapter's own `state`. A
`null` from `resolve` is an unresolved import: it is kept as an edge and named in the report, never
dropped.

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
