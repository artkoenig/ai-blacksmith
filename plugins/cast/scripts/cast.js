#!/usr/bin/env node
'use strict'
// cast - the module graph of a project, and what is wrong with it.
//
//   cast scan [--root <dir>]     writes <root>/.cast/graph.json
//   cast report [--root <dir>]   reads it and says what is wrong
//   cast edges --from <layer> --to <layer> [--root <dir>]
//                                the module edges behind one layer edge
//
// The engine holds no language knowledge. Every fact about a language - which
// files are modules, which text is an import, what kind of edge it makes, how a
// specifier resolves - comes from an adapter file. Adapters ship in
// ../adapters/, and a project adds its own in <root>/.cast/adapters/.
const fs = require('fs')
const path = require('path')

const SHIPPED = path.join(__dirname, '..', 'adapters')
const ALWAYS_IGNORED = ['.git', '.cast', '.claude', '.forge']

function die(msg) {
  process.stderr.write(msg + '\n')
  process.exit(2)
}

// --- adapters ---------------------------------------------------------------

function loadAdapters(root) {
  const dirs = [SHIPPED, path.join(root, '.cast', 'adapters')]
  const out = []
  for (const dir of dirs) {
    let names = []
    try {
      names = fs.readdirSync(dir).filter((n) => n.endsWith('.js')).sort()
    } catch {
      continue
    }
    for (const n of names) {
      const mod = require(path.join(dir, n))
      if (!mod || !Array.isArray(mod.extensions) || !Array.isArray(mod.patterns))
        die(`adapter ${path.join(dir, n)} declares no extensions or patterns`)
      out.push(mod)
    }
  }
  if (!out.length) die('no adapter found: cast cannot read any language')
  return out
}

// --- the tree ---------------------------------------------------------------

function makeCtx(root) {
  const stat = (rel) => {
    try {
      return fs.statSync(path.join(root, rel))
    } catch {
      return null
    }
  }
  return {
    root,
    exists: (rel) => stat(rel) !== null,
    isFile: (rel) => {
      const s = stat(rel)
      return s !== null && s.isFile()
    },
    read: (rel) => {
      try {
        return fs.readFileSync(path.join(root, rel), 'utf8')
      } catch {
        return null
      }
    },
  }
}

function walk(root, ignore, keep) {
  const files = []
  const step = (rel) => {
    let entries = []
    try {
      entries = fs.readdirSync(path.join(root, rel), { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries.sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const child = rel ? rel + '/' + e.name : e.name
      if (e.isDirectory()) {
        if (ignore.has(e.name) || e.name.startsWith('.')) continue
        step(child)
      } else if (e.isFile() && keep(child)) {
        files.push(child)
      }
    }
  }
  step('')
  return files
}

// --- parsing ----------------------------------------------------------------

// The site is the line the import statement starts on, so an import spread over
// several lines is reported where a reader would look for it, not at the `from`.
function lineOf(text, index) {
  let n = 1
  for (let i = 0; i < index && i < text.length; i++) if (text[i] === '\n') n++
  return n
}

// One (line, specifier) makes one edge. The adapter's pattern order decides
// which kind claims it: `import type` matches a value pattern too, and must not
// be counted twice or classified as the looser of the two.
function imports(text, adapter) {
  const seen = new Map()
  for (const { kind, re } of adapter.patterns) {
    const rx = new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g')
    let m
    while ((m = rx.exec(text)) !== null) {
      if (m[0].length === 0) rx.lastIndex++
      const spec = m[1]
      if (!spec) continue
      const line = lineOf(text, m.index + Math.max(0, m[0].search(/\S/)))
      const key = line + '\0' + spec
      if (!seen.has(key)) seen.set(key, { target: spec, kind, line })
    }
  }
  return [...seen.values()].sort((a, b) => a.line - b.line || (a.target < b.target ? -1 : 1))
}


// --- layers -----------------------------------------------------------------

// A layer is the altitude the graph is read at. `<root>/.cast/layers.json` maps
// globs to layer names, first match wins, so the file's order is the priority.
// Without that file the first directory level is the layer - enough to open a
// view on any project, and no wizard.
const UNASSIGNED = 'unassigned'

function globToRe(glob) {
  let re = ''
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i]
    if (c === '*') {
      if (glob[i + 1] === '*') {
        i++
        // `**/` spans whole path segments, including none at all, so `src/**/*.ts`
        // still matches `src/a.ts`.
        if (glob[i + 1] === '/') {
          i++
          re += '(?:[^/]+/)*'
        } else re += '.*'
      } else re += '[^/]*'
    } else if (c === '?') re += '[^/]'
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }
  return new RegExp('^' + re + '$')
}

function layerRules(root) {
  let raw
  try {
    raw = JSON.parse(fs.readFileSync(path.join(root, '.cast', 'layers.json'), 'utf8'))
  } catch {
    return null
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw))
    die(`${path.join(root, '.cast', 'layers.json')} is not an object mapping globs to layer names`)
  return Object.entries(raw).map(([glob, name]) => ({ glob, name: String(name), re: globToRe(glob) }))
}

function layerOf(id, rules) {
  if (!rules) {
    const i = id.indexOf('/')
    return i === -1 ? '.' : id.slice(0, i)
  }
  for (const r of rules) if (r.re.test(id)) return r.name
  // A module no glob claims is never dropped: it is named, and the count says so.
  return UNASSIGNED
}

// Every module lands in exactly one layer - the map is keyed by module id, so a
// second matching glob cannot add a second placement.
function assign(graph, rules) {
  const of = new Map()
  for (const m of graph.modules) of.set(m.id, layerOf(m.id, rules))
  const names = []
  if (rules) for (const r of rules) if (r.name !== UNASSIGNED && !names.includes(r.name)) names.push(r.name)
  for (const m of graph.modules) {
    const l = of.get(m.id)
    if (l !== UNASSIGNED && !names.includes(l)) names.push(l)
  }
  return { of, names }
}

// The module edges behind one layer edge. Only edges that landed on a module
// have a far layer at all; an unresolved or external one is reported by name in
// `cast report`, not here.
function layerEdges(graph, of, from, to) {
  const out = []
  for (const m of graph.modules) {
    if (of.get(m.id) !== from) continue
    for (const e of m.edges) {
      if (e.resolution !== 'module') continue
      if (of.get(e.to) !== to) continue
      out.push(e)
    }
  }
  return out.sort((a, b) => (a.file < b.file ? -1 : a.file > b.file ? 1 : a.line - b.line))
}

// --- scan -------------------------------------------------------------------

function scan(root) {
  const adapters = loadAdapters(root)
  const ctx = makeCtx(root)
  const byExt = new Map()
  const ignore = new Set(ALWAYS_IGNORED)
  for (const a of adapters) {
    a.state = a.init ? a.init({ ...ctx, state: null }) : null
    for (const e of a.extensions) byExt.set(e, a)
    for (const d of a.ignore || []) ignore.add(d)
  }

  const files = walk(root, ignore, (rel) => byExt.has(path.posix.extname(rel)))
  const known = new Set(files)
  const modules = []
  for (const id of files) {
    const adapter = byExt.get(path.posix.extname(id))
    const text = ctx.read(id) || ''
    const edges = []
    for (const imp of imports(text, adapter)) {
      const answer = adapter.resolve(imp.target, id, { ...ctx, state: adapter.state }) || null
      // The site travels with the edge: without the file and the line, a report
      // names a problem nobody can open.
      const edge = {
        target: imp.target,
        kind: imp.kind,
        file: id,
        line: imp.line,
        to: null,
        resolution: 'unresolved',
      }
      if (answer && answer.to && known.has(answer.to)) {
        edge.to = answer.to
        edge.resolution = 'module'
      } else if (answer && (answer.external || answer.to)) {
        edge.resolution = 'external'
      }
      edges.push(edge)
    }
    modules.push({ id, adapter: adapter.name || 'unnamed', edges })
  }

  return {
    version: 1,
    root,
    adapters: adapters.map((a) => a.name || 'unnamed'),
    modules,
  }
}

// --- report -----------------------------------------------------------------

// Tarjan: every module of a cycle belongs to the same strongly connected
// component, so the whole component is what gets named - entering the cycle at a
// different module cannot change the answer.
function cycles(graph) {
  const succ = new Map()
  for (const m of graph.modules)
    succ.set(m.id, m.edges.filter((e) => e.resolution === 'module').map((e) => e.to))
  const index = new Map()
  const low = new Map()
  const onStack = new Set()
  const stack = []
  const found = []
  let next = 0

  for (const start of succ.keys()) {
    if (index.has(start)) continue
    // Iterative: a deep tree would blow a recursive stack on a real project.
    const work = [[start, 0]]
    index.set(start, next)
    low.set(start, next++)
    stack.push(start)
    onStack.add(start)
    while (work.length) {
      const frame = work[work.length - 1]
      const [v, i] = frame
      const kids = succ.get(v) || []
      if (i < kids.length) {
        frame[1]++
        const w = kids[i]
        if (!succ.has(w)) continue
        if (!index.has(w)) {
          index.set(w, next)
          low.set(w, next++)
          stack.push(w)
          onStack.add(w)
          work.push([w, 0])
        } else if (onStack.has(w)) {
          low.set(v, Math.min(low.get(v), index.get(w)))
        }
        continue
      }
      work.pop()
      if (work.length) {
        const parent = work[work.length - 1][0]
        low.set(parent, Math.min(low.get(parent), low.get(v)))
      }
      if (low.get(v) === index.get(v)) {
        const comp = []
        let w
        do {
          w = stack.pop()
          onStack.delete(w)
          comp.push(w)
        } while (w !== v)
        const selfLoop = comp.length === 1 && (succ.get(comp[0]) || []).includes(comp[0])
        if (comp.length > 1 || selfLoop) found.push(comp.sort())
      }
    }
  }
  return found.sort((a, b) => (a[0] < b[0] ? -1 : 1))
}

function report(graph, rules) {
  const out = []
  const edges = graph.modules.flatMap((m) => m.edges)
  const kinds = {}
  for (const e of edges) kinds[e.kind] = (kinds[e.kind] || 0) + 1
  const kindLine = Object.keys(kinds)
    .sort()
    .map((k) => `${k} ${kinds[k]}`)
    .join(', ')
  out.push(`modules ${graph.modules.length}`)
  out.push(`edges ${edges.length}${kindLine ? ` (${kindLine})` : ''}`)

  const { of, names } = assign(graph, rules)
  const count = (l) => graph.modules.filter((m) => of.get(m.id) === l).length
  out.push(`layers ${names.length}`)
  for (const n of names) out.push(`  ${n} ${count(n)}`)
  const orphans = graph.modules.filter((m) => of.get(m.id) === UNASSIGNED)
  out.push(`unassigned ${orphans.length}`)
  // Named, not just counted: a module nobody placed is a layers.json to fix.
  for (const m of orphans) out.push(`  ${m.id}`)

  const unresolved = edges.filter((e) => e.resolution === 'unresolved')
  out.push(`unresolved ${unresolved.length}`)
  // Every one of them is named. An unresolved import that is only counted is an
  // import nobody can go and fix.
  for (const e of unresolved) out.push(`  ${e.file}:${e.line} ${e.target} (${e.kind})`)

  const found = cycles(graph)
  out.push(`cycles ${found.length}`)
  for (const c of found) out.push(`  cycle: ${c.join(' -> ')}`)
  return out.join('\n')
}

function readGraph(out) {
  try {
    return JSON.parse(fs.readFileSync(out, 'utf8'))
  } catch {
    die(`no graph at ${out}: run cast scan first`)
  }
}

// --- cli --------------------------------------------------------------------

const USAGE =
  'usage: cast <scan|report> [--root <dir>]\n' +
  '       cast edges --from <layer> --to <layer> [--root <dir>]'

function main(argv) {
  const cmd = argv[0]
  let root = process.cwd()
  let from = null
  let to = null
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--root' && argv[i + 1]) root = path.resolve(argv[++i])
    else if (cmd === 'edges' && argv[i] === '--from' && argv[i + 1]) from = argv[++i]
    else if (cmd === 'edges' && argv[i] === '--to' && argv[i + 1]) to = argv[++i]
    else die(USAGE)
  }
  const out = path.join(root, '.cast', 'graph.json')

  if (cmd === 'scan') {
    const graph = scan(root)
    fs.mkdirSync(path.dirname(out), { recursive: true })
    fs.writeFileSync(out, JSON.stringify(graph, null, 2) + '\n')
    process.stdout.write(`${graph.modules.length} modules scanned into ${path.relative(root, out)}\n`)
    return 0
  }
  if (cmd === 'report') {
    const graph = readGraph(out)
    process.stdout.write(report(graph, layerRules(root)) + '\n')
    return 0
  }
  if (cmd === 'edges') {
    if (!from || !to) die(USAGE)
    const graph = readGraph(out)
    const { of } = assign(graph, layerRules(root))
    const found = layerEdges(graph, of, from, to)
    const lines = [`edges ${from} -> ${to} ${found.length}`]
    // Each one with its file and its line: a layer edge is only actionable
    // where the imports behind it can be opened.
    for (const e of found) lines.push(`  ${e.file}:${e.line} -> ${e.to} (${e.kind})`)
    process.stdout.write(lines.join('\n') + '\n')
    return 0
  }
  die(USAGE)
}

if (require.main === module) process.exit(main(process.argv.slice(2)))
module.exports = { scan, report, cycles, imports, layerRules, layerOf, assign, layerEdges }
