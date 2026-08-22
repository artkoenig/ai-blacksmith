# cast

The module graph of a project, and what is wrong with it.

```
cast scan [--root <dir>]     writes <root>/.cast/graph.json
cast report [--root <dir>]   reads it and says what is wrong
```

`scan` writes one entry per source module with its outgoing edges. Every edge carries the
specifier it came from, its kind (`value`, `type`, `dynamic`), the file and the line of the import
that produced it, and where it resolved to: another module, something outside the project, or
nothing at all.

`report` counts the modules and the edges by kind, names every import that resolved to nothing,
and names every module of every dependency cycle - the whole strongly connected component, not the
module the walk entered it through.

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
