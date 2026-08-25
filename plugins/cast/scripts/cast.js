#!/usr/bin/env node
'use strict'
// cast - the module graph of a project, and what is wrong with it.
//
//   cast scan [--root <dir>]     writes the graph to a scratch directory keyed
//                                by the root, and prints the file it wrote
//   cast report [--root <dir>]   reads it and says what is wrong
//   cast check [--root <dir>]    the rules of <root>/.cast/rules.json, evaluated
//                                against the module graph; exit 1 on an error
//   cast plan simulate <name|file> [--root <dir>]
//                                a refactoring written down before it is done:
//                                <root>/.cast/plans/<name>.json applied to a copy
//                                of the graph, before and after, writing nothing
//   cast baseline [--update] [--root <dir>]
//                                the inherited violations <root>/.cast/baseline.json
//                                holds; --update rewrites it, and refuses to grow it
//   cast edges --from <layer> --to <layer> [--root <dir>]
//                                the module edges behind one layer edge
//   cast render --mermaid [--expand <layer>] [--plan <name|file>] [--root <dir>]
//   cast render --html <file> [--fragment] [--expand <layer>] [--plan <name|file>] [--root <dir>]
//                                the graph at layer altitude, one layer resolved;
//                                --plan draws the graph the plan would leave,
//                                writing nothing but the page that was asked for
//
// The engine holds no language knowledge. Every fact about a language - which
// files are modules, which text is an import, what kind of edge it makes, how a
// specifier resolves - comes from an adapter file. Adapters ship in
// ../adapters/, and a project adds its own in <root>/.cast/adapters/.
const fs = require('fs')
const os = require('os')
const path = require('path')
const crypto = require('crypto')

const SHIPPED = path.join(__dirname, '..', 'adapters')
const ALWAYS_IGNORED = ['.git', '.cast', '.claude', '.forge']

// Exit 2 is "cast could not run", and every validation failure goes through it.
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

// An import written in a comment is not an import. The engine knows no comment
// syntax: the adapter's optional `comments` says what opens one, and what a
// string literal is, because a `//` inside a string opens nothing. An adapter
// that says nothing is matched over its whole text, as before.
//
// Comments are blanked, not removed: every character keeps its offset and every
// newline stays, so the line an import is reported at is the line it is on.
// String literals are left standing - the specifier lives in one - and are only
// skipped over, with a template literal's `${}` read as code again so a require
// inside one keeps its edge.
//
// `regex` is for a literal whose delimiter is also an operator, like javascript's
// `/`: a quote inside one is no string, so it is spanned in one step and blanked.
// It opens only where the delimiter cannot be the operator - `notAfter` is tested
// against the last character of code before it - and only where it closes on the
// same line, so a division that opens nothing swallows nothing.
function mask(text, spec) {
  if (!spec) return text
  const lines = spec.line || []
  const blocks = spec.block || []
  const strings = spec.strings || []
  const regexes = spec.regex || []
  const out = text.split('')
  const stack = [] // interpolations open: the string they are in, and its brace depth
  let str = null // the string literal being read, or null in code
  let i = 0
  const at = (t) => !!t && text.startsWith(t, i)
  while (i < text.length) {
    if (str) {
      if (str.escape && at(str.escape)) {
        i += str.escape.length + 1
      } else if (str.interpolate && at(str.interpolate[0])) {
        stack.push({ str, depth: 0 })
        i += str.interpolate[0].length
        str = null
      } else if (at(str.close)) {
        i += str.close.length
        str = null
      } else i++
      continue
    }
    const l = lines.find(at)
    if (l) {
      for (; i < text.length && text[i] !== '\n'; i++) out[i] = ' '
      continue
    }
    const b = blocks.find(([open]) => at(open))
    if (b) {
      const end = text.indexOf(b[1], i + b[0].length)
      const stop = end === -1 ? text.length : end + b[1].length
      for (; i < stop; i++) if (text[i] !== '\n') out[i] = ' '
      continue
    }
    const s = strings.find((x) => at(x.open))
    if (s) {
      str = s
      i += s.open.length
      continue
    }
    // A regex literal: opened only where the delimiter is no operator, and
    // spanned to its close in one step, so a quote in a character class opens
    // no string. Comments are already blanks, so the character before it is
    // the last of the code.
    const rx = regexes.find((x) => at(x.open) && !x.notAfter.test(last(out, i)))
    const end = rx ? span(text, rx, i) : -1
    if (end !== -1) {
      for (; i < end; i++) out[i] = ' '
      continue
    }
    // Inside a `${}`, the brace that closes it is the one that returns to the
    // string; a brace of the code in between is not.
    const top = stack[stack.length - 1]
    if (top) {
      const close = top.str.interpolate[1]
      if (at(close)) {
        if (top.depth === 0) {
          stack.pop()
          str = top.str
        } else top.depth--
        i += close.length
        continue
      }
      if (text[i] === '{') top.depth++
    }
    i++
  }
  return out.join('')
}

// The last character of code before `i`, whitespace and blanked comments skipped.
function last(out, i) {
  let j = i - 1
  while (j >= 0 && /\s/.test(out[j])) j--
  return j < 0 ? '' : out[j]
}

// Where the literal opened at `i` closes, or -1 where it does not close on its
// line. Inside a `class` pair - a character class - the close token is content.
function span(text, spec, i) {
  let cls = false
  for (let j = i + spec.open.length; j < text.length; j++) {
    if (text[j] === '\n') return -1
    if (spec.escape && text.startsWith(spec.escape, j)) {
      j += spec.escape.length
      continue
    }
    if (spec.class) {
      if (!cls && text[j] === spec.class[0]) cls = true
      else if (cls && text[j] === spec.class[1]) cls = false
      if (cls) continue
    }
    if (text.startsWith(spec.close, j)) return j + spec.close.length
  }
  return -1
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

// No layers.json at all is the documented default, and the only thing the
// directory-level fallback answers for. A file that is there but cannot be read
// or parsed is not that: falling back on it would read the graph at an altitude
// nobody declared and call it the project's own, so it is exit 2 like every
// other file cast cannot run on.
function layerRules(root) {
  const file = path.join(root, '.cast', 'layers.json')
  let text
  try {
    text = fs.readFileSync(file, 'utf8')
  } catch (e) {
    if (e.code === 'ENOENT') return null
    die(`${file} could not be read: ${e.message}`)
  }
  let raw
  try {
    raw = JSON.parse(text)
  } catch (e) {
    die(`${file} is not valid JSON: ${e.message}`)
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw))
    die(`${file} is not an object mapping globs to layer names`)
  // A value that is not a layer name is the file's own error. Coercing it would
  // invent a layer named `[object Object]` and place modules in it, an altitude
  // nobody declared - the same answer the unreadable file gets.
  for (const [glob, name] of Object.entries(raw))
    if (typeof name !== 'string' || !name)
      die(`${file} maps ${glob} to ${JSON.stringify(name)}, not a layer name`)
  return Object.entries(raw).map(([glob, name]) => ({ glob, name, re: globToRe(glob) }))
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

// --- render -----------------------------------------------------------------

// Every view opens at layer altitude: one node per layer, none per module. A
// module only becomes a node where `--expand` asks for its layer, so the picture
// stays readable on a project no reader can hold in their head.
function layerList(graph, of, names) {
  const all = names.slice()
  if (graph.modules.some((m) => of.get(m.id) === UNASSIGNED)) all.push(UNASSIGNED)
  return all
}

// Mermaid ids may not carry `/`, `.` or a space, so the id is escaped and the
// name travels in the quoted label - the label is what a reader matches on.
// Each character mermaid rejects becomes `_<hex>_`, which is reversible: mapping
// them all to a bare `_` would give `src/a-b.ts` and `src/a_b.ts` one id, and one
// node drawn for two modules is a graph that hides an edge.
function nodeId(prefix, name) {
  return prefix + name.replace(/[^A-Za-z0-9]/g, (c) => '_' + c.charCodeAt(0).toString(16) + '_')
}

// The one description every view draws from: the layers with the modules they
// hold, every resolved module edge with its site and whatever rule it breaks,
// and the counts `cast report` and `cast check` print. The page carries this
// object verbatim, so no number it shows was computed anywhere else.
function viewData(graph, rules, checkRules, baseline) {
  const { of, names } = assign(graph, rules)
  const all = layerList(graph, of, names)
  const forbidden = checkRules ? checkRules.forbidden : []
  const found = violations(graph, of, { forbidden, allowed: checkRules ? checkRules.allowed : [] })
  const { live, held } = partition(found, baseline || null)
  // A site is the file, the line, the module imported and the kind - the same
  // shape `cast check` lists. A live violation wins over an inherited one on the
  // same site: the breaking mark is the one a reader must not miss.
  const siteKey = (v) => [v.file, v.line, v.to, v.kind].join('\0')
  const mark = new Map()
  for (const v of held) mark.set(siteKey(v), { rule: v.rule, severity: v.severity, state: 'inherited' })
  for (const v of live) mark.set(siteKey(v), { rule: v.rule, severity: v.severity, state: 'breaking' })
  const edges = []
  for (const m of graph.modules) {
    for (const e of m.edges) {
      if (e.resolution !== 'module') continue
      const site = { from: m.id, to: e.to, file: e.file, line: e.line, kind: e.kind }
      const v = mark.get(siteKey({ file: e.file, line: e.line, to: e.to, kind: e.kind }))
      if (v) Object.assign(site, v)
      edges.push(site)
    }
  }
  const allEdges = graph.modules.flatMap((m) => m.edges)
  const byResolution = (r) => allEdges.filter((e) => e.resolution === r).length
  return {
    layers: all.map((l) => ({
      name: l,
      modules: graph.modules.filter((m) => of.get(m.id) === l).map((m) => m.id),
    })),
    edges,
    counts: {
      modules: graph.modules.length,
      edges: allEdges.length,
      moduleEdges: moduleEdges(graph),
      layers: names.length,
      unassigned: graph.modules.filter((m) => of.get(m.id) === UNASSIGNED).length,
      unresolved: byResolution('unresolved'),
      opaque: byResolution('opaque'),
      cycles: cycles(graph).length,
      violations: live.length,
      errors: live.filter((v) => v.severity === 'error').length,
      baselined: held.length,
      rules: forbidden.length,
    },
  }
}

// The expansion mermaid draws: two altitudes, a layer or its modules, opened by
// `cast render --mermaid --expand`. The page no longer calls it - it draws the
// containment tree below, whose functions `html` inlines instead. Both read the
// same `data`, so the two pictures answer for one graph at the altitude each of
// them has.
function viewAt(data, expand) {
  const esc = (p, n) => p + n.replace(/[^A-Za-z0-9]/g, (c) => '_' + c.charCodeAt(0).toString(16) + '_')
  const of = new Map()
  for (const l of data.layers) for (const m of l.modules) of.set(m, l.name)
  const nodes = []
  for (const l of data.layers) {
    if (l.name === expand)
      for (const m of l.modules) nodes.push({ id: esc('M_', m), label: m, layer: l.name, module: m })
    else nodes.push({ id: esc('L_', l.name), label: l.name + ' (' + l.modules.length + ')', layer: l.name, module: null })
  }
  const end = (m) => (of.get(m) === expand ? esc('M_', m) : esc('L_', of.get(m)))
  // The weight is the number of module edges behind the layer edge: without it a
  // layer arrow hides whether it stands for one import or two hundred. An edge
  // inside one collapsed layer has no arrow to draw at this altitude.
  const by = new Map()
  for (const e of data.edges) {
    const a = end(e.from)
    const b = end(e.to)
    if (a === b) continue
    const k = a + '\0' + b
    let g = by.get(k)
    if (!g) {
      g = { from: a, to: b, weight: 0, sites: [], rule: null, severity: null, state: null }
      by.set(k, g)
    }
    g.weight++
    g.sites.push(e)
    if (e.rule && g.state !== 'breaking') {
      g.rule = e.rule
      g.severity = e.severity
      g.state = e.state
    }
  }
  const edges = [...by.keys()].sort().map((k) => by.get(k))
  for (const g of edges) {
    // The severity is the colour and the rule name is the label, in both views:
    // an edge nobody flagged keeps the label it always had, the bare weight.
    g.color = !g.state ? '#666' : g.state === 'inherited' ? '#888' : g.severity === 'warn' ? '#e08b00' : '#d32f2f'
    // The tone is the name of the severity's colour, and the page takes the
    // colour itself from the sheet: an arrow drawn with a literal would keep a
    // light theme's red on a dark ground.
    g.tone = !g.state ? 'plain' : g.state === 'inherited' ? 'inherited' : g.severity === 'warn' ? 'warn' : 'error'
    g.label = g.rule ? g.weight + ' ' + g.rule + (g.state === 'inherited' ? ' (inherited)' : '') : String(g.weight)
  }
  return { nodes, edges, expand: expand || null, counts: data.counts }
}

// Where every node and every arrow sits, in numbers alone - the page needs no
// layout library, and this runs in node too, which is where it is tested. Rank
// is the longest path in, relaxed until it settles; a cycle stops it at the node
// count rather than spinning.
function layout(view) {
  const W = 190
  const H = 40
  const GAPX = 110
  const GAPY = 26
  const PAD = 24
  const rank = new Map(view.nodes.map((n) => [n.id, 0]))
  for (let pass = 0; pass < view.nodes.length; pass++) {
    let moved = false
    for (const e of view.edges) {
      if (!rank.has(e.from) || !rank.has(e.to)) continue
      if (rank.get(e.to) < rank.get(e.from) + 1) {
        rank.set(e.to, rank.get(e.from) + 1)
        moved = true
      }
    }
    if (!moved) break
  }
  const columns = new Map()
  const nodes = []
  for (const n of view.nodes) {
    const r = rank.get(n.id)
    const row = columns.get(r) || 0
    columns.set(r, row + 1)
    nodes.push({ ...n, x: PAD + r * (W + GAPX), y: PAD + row * (H + GAPY), w: W, h: H })
  }
  const at = new Map(nodes.map((n) => [n.id, n]))
  const edges = view.edges.map((e) => {
    const a = at.get(e.from)
    const b = at.get(e.to)
    return {
      ...e,
      x1: a.x + a.w,
      y1: a.y + a.h / 2,
      x2: b.x,
      y2: b.y + b.h / 2,
      mx: (a.x + a.w + b.x) / 2,
      my: (a.y + b.y + a.h) / 2,
    }
  })
  // An expanded layer is boxed around its modules, and the box is what a reader
  // clicks to collapse it again - the layer node itself is gone at that altitude.
  const groups = []
  if (view.expand) {
    const mine = nodes.filter((n) => n.layer === view.expand)
    if (mine.length) {
      const x = Math.min(...mine.map((n) => n.x))
      const y = Math.min(...mine.map((n) => n.y))
      groups.push({
        layer: view.expand,
        x: x - 12,
        y: y - 30,
        w: Math.max(...mine.map((n) => n.x + n.w)) - x + 24,
        h: Math.max(...mine.map((n) => n.y + n.h)) - y + 42,
      })
    }
  }
  const right = nodes.concat(groups.map((g) => ({ x: g.x, y: g.y, w: g.w, h: g.h })))
  return {
    nodes,
    edges,
    groups,
    expand: view.expand,
    counts: view.counts,
    width: Math.max(...right.map((n) => n.x + n.w), 0) + PAD,
    height: Math.max(...right.map((n) => n.y + n.h), 0) + PAD,
  }
}

// --- the tree the page draws ------------------------------------------------
// Mermaid knows two altitudes, a layer or its modules. The page knows one tree:
// the layer, then every folder level of the module id, then the file. A node at
// any depth opens in place, and every arrow runs between two closed ones.
//
// The same rule as `viewAt` holds for every function below: `html` inlines them
// by `toString()`, so they close over nothing this module holds. A call between
// them is fine - they travel together - but a reference to anything else here
// would be undefined in the page.

// The id is the containment key with every character an html id or a `querySelector`
// would trip over escaped to `_<hex>_`, reversibly: mapping them all to `_` would
// give `src/a-b.ts` and `src/a_b.ts` one node, and one node for two files hides an
// import.
function treeId(key) {
  return 'N_' + key.replace(/[^A-Za-z0-9]/g, (c) => '_' + c.charCodeAt(0).toString(16) + '_')
}

// The containment tree over the whole project. A node is keyed by its path from
// the root - the layer name, then each folder level - so two layers holding the
// same folder keep two nodes, and the id of a node is derived from that key
// alone: the page can name what to open without carrying a cursor.
function treeOf(data) {
  const root = { id: 'ROOT', key: '', label: '', kind: 'root', module: null, children: [], modules: [] }
  const child = (parent, key, label, kind, module) => {
    let n = parent.children.find((x) => x.key === key)
    if (!n) {
      n = { id: treeId(key), key, label, kind, module, children: [], modules: [] }
      parent.children.push(n)
    }
    return n
  }
  for (const l of data.layers) {
    const layer = child(root, l.name, l.name, 'layer', null)
    for (const m of l.modules) {
      const parts = m.split('/')
      let cur = layer
      let key = l.name
      for (let i = 0; i < parts.length; i++) {
        key += '/' + parts[i]
        const leaf = i === parts.length - 1
        cur = child(cur, key, parts[i], leaf ? 'file' : 'folder', leaf ? m : null)
      }
    }
  }
  // Every node carries the modules of its whole subtree. That is what an arrow
  // reads to find the closed node an import is drawn from, and what the count in
  // a label stands for.
  const fill = (n) => {
    n.modules = n.module ? [n.module] : n.children.reduce((a, c) => a.concat(fill(c)), [])
    if (n.kind === 'layer' || n.kind === 'folder') n.label = n.label + ' (' + n.modules.length + ')'
    return n.modules
  }
  fill(root)
  return root
}

// The tree at one state of opening. `open` is the ids that are open; everything
// else is a closed box. An open node keeps its own node and holds its children,
// a closed one stands for every module below it.
function viewTree(data, open) {
  const isOpen = {}
  for (const id of open || []) isOpen[id] = true
  const root = treeOf(data)
  // `hasChildren` outlives the closing: a closed node drops its children from the
  // view, and without the flag nothing left in the page could tell a group from a
  // file, which is the marker's whole question.
  const show = (n) => {
    const o = n.children.length > 0 && isOpen[n.id] === true
    return { ...n, hasChildren: n.children.length > 0, open: o, children: o ? n.children.map(show) : [] }
  }
  const nodes = root.children.map(show)
  // Where a module is drawn: the deepest visible node holding it, which is by
  // construction a closed one. An arrow never lands on an open ancestor.
  const flat = []
  const at = {}
  const walk = (n) => {
    flat.push(n)
    if (n.open) n.children.forEach(walk)
    else for (const m of n.modules) at[m] = n.id
  }
  nodes.forEach(walk)
  const by = new Map()
  for (const e of data.edges) {
    const a = at[e.from]
    const b = at[e.to]
    // An import between two modules the same closed node holds has no arrow to
    // draw: it is inside the box, and opening that box is what reveals it.
    if (!a || !b || a === b) continue
    const k = a + '\0' + b
    let g = by.get(k)
    if (!g) {
      g = { from: a, to: b, weight: 0, sites: [], rule: null, severity: null, state: null }
      by.set(k, g)
    }
    g.weight++
    g.sites.push(e)
    if (e.rule && g.state !== 'breaking') {
      g.rule = e.rule
      g.severity = e.severity
      g.state = e.state
    }
  }
  const edges = [...by.keys()].sort().map((k) => by.get(k))
  for (const g of edges) {
    g.color = !g.state ? '#666' : g.state === 'inherited' ? '#888' : g.severity === 'warn' ? '#e08b00' : '#d32f2f'
    // The tone is the name of the severity's colour, and the page takes the
    // colour itself from the sheet: an arrow drawn with a literal would keep a
    // light theme's red on a dark ground.
    g.tone = !g.state ? 'plain' : g.state === 'inherited' ? 'inherited' : g.severity === 'warn' ? 'warn' : 'error'
    g.label = g.rule ? g.weight + ' ' + g.rule + (g.state === 'inherited' ? ' (inherited)' : '') : String(g.weight)
    // The kinds behind the arrow, counted. Without them a type import a rule's
    // `kinds` deliberately spares looks exactly like a value import no rule
    // names: both unmarked arrows, and the reader cannot tell which is which.
    const order = ['value', 'type', 'dynamic']
    const rank = (k) => (order.indexOf(k) < 0 ? order.length : order.indexOf(k))
    g.kindCounts = {}
    for (const s of g.sites) g.kindCounts[s.kind] = (g.kindCounts[s.kind] || 0) + 1
    g.kinds = Object.keys(g.kindCounts).sort((x, y) => rank(x) - rank(y) || (x < y ? -1 : x > y ? 1 : 0))
    g.kindLabel = g.kinds.map((k) => g.kindCounts[k] + ' ' + k).join(', ')
  }
  return { nodes, flat, edges, open: (open || []).slice(), counts: data.counts }
}

// Where every box and every arrow sits, in numbers alone. The layout is one
// vertical stack at every level: a closed node is one box of a fixed height, an
// open one is a header and its children stacked inside it, so a box is only ever
// as tall as what it shows. An arrow runs beside the stack, on the side its
// direction gives it: down the right of the boxes, up the left of them.
// Every number a finger has to hit is `TAP`: the header of a node and the height
// of a closed box. 44 css pixels is the smallest target a press lands on
// reliably, so it is the floor for `H` and `HEAD` rather than a value the page
// adds on top. `CLEAR` is not one of them - it is how far an arrow stands off the
// boxes, and a curve is not pressed by aiming at the gap beside it.
function layoutTree(view) {
  const M = { W: 220, H: 44, HEAD: 44, GAP: 8, PAD: 10, CLEAR: 16, TAP: 44 }
  const clone = (n) => ({ ...n, children: n.children.map(clone) })
  const size = (n) => {
    if (!n.open) {
      n.w = M.W
      n.h = M.H
      return n
    }
    n.children.forEach(size)
    n.w = M.PAD * 2 + Math.max(...n.children.map((c) => c.w))
    n.h = M.HEAD + M.PAD + n.children.reduce((s, c) => s + c.h, 0) + M.GAP * (n.children.length - 1)
    return n
  }
  // The header is a band of its own across the top of the box: the control that
  // opens and closes the node. The children start below it, so the ground of an
  // open box belongs to no control and a press there does nothing.
  const place = (n, x, y) => {
    n.x = x
    n.y = y
    n.hx = x
    n.hy = y
    n.hw = n.w
    n.hh = Math.min(M.HEAD, n.h)
    let cy = y + M.HEAD
    for (const c of n.children) {
      place(c, x + M.PAD, cy)
      cy += c.h + M.GAP
    }
  }
  const roots = view.nodes.map(clone)
  let y = M.PAD
  for (const n of roots) {
    size(n)
    // The stack starts one `CLEAR` in from the edge: an arrow running up passes
    // to the left of the outermost box, and that is the only room it needs -
    // every box it could stand off is at this x or further in.
    place(n, M.PAD + M.CLEAR, y)
    y += n.h + M.GAP
  }
  const flat = []
  const collect = (n) => {
    flat.push(n)
    n.children.forEach(collect)
  }
  roots.forEach(collect)
  const at = new Map(flat.map((n) => [n.id, n]))
  const right = Math.max(...flat.map((n) => n.x + n.w), 0)
  // An arrow is a curve and nothing else: no box, no digits, no backing, no head.
  // What it carries travels with it as data - `weight`, `label`, `kinds`, `rule`,
  // `sites` - and is read out on demand, by pressing the arrow or by pointing at
  // one of the nodes it joins. The labels of both ends come along so the panel
  // can name a neighbour without the drawing.
  //
  // The side is the direction. An import of something further down the stack
  // leaves and arrives on the right of the boxes, one of something further up on
  // the left, so which way a dependency runs is read off the drawing without a
  // head on every curve - and it stays readable where a page full of modules
  // would be a page full of arrowheads.
  //
  // No arrow reserves a lane. `mx` is the far side of what the arrow actually
  // passes - the boxes its span crosses, one `CLEAR` beyond the outermost of
  // them - so a curve between neighbours is nearly flat and only one that spans
  // the page stands far off it. Two arrows over the same stretch share that
  // column: they are told apart by their ends and their colour, not by a lane
  // each, which is what made the drawing sprawl.
  const spans = (n, y1, y2) => n.y < Math.max(y1, y2) && n.y + n.h > Math.min(y1, y2)
  const holds = (n, m) => n.key === m.key || m.key.indexOf(n.key + '/') === 0
  const edges = view.edges.map((e) => {
    const a = at.get(e.from)
    const b = at.get(e.to)
    const y1 = a.y + a.h / 2
    const y2 = b.y + b.h / 2
    const down = y2 >= y1
    const x1 = down ? a.x + a.w : a.x
    const x2 = down ? b.x + b.w : b.x
    // A box the arrow only passes stands in its way. A box holding both ends is
    // the room it runs in: clearing that one would send an arrow between two
    // children out around their parent, which is the sprawl again.
    const past = flat.filter((n) => n !== a && n !== b && !(holds(n, a) && holds(n, b)) && spans(n, y1, y2))
    const mx = down
      ? Math.max(x1, x2, ...past.map((n) => n.x + n.w)) + M.CLEAR
      : Math.min(x1, x2, ...past.map((n) => n.x)) - M.CLEAR
    return { ...e, x1, y1, x2, y2, mx, down, fromLabel: a.label, toLabel: b.label }
  })
  return {
    nodes: roots,
    flat,
    edges,
    open: view.open,
    counts: view.counts,
    metrics: M,
    // The drawing ends at the furthest arrow and at the last box: nothing beside
    // an arrow widens it and nothing under one makes it taller.
    width: Math.max(right, ...edges.map((e) => e.mx)) + M.PAD,
    height: Math.max(...flat.map((n) => n.y + n.h), 0) + M.PAD,
  }
}

// What a node's header says about itself: closed, open, or nothing at all where
// there is nothing to open. A node without children carries no marker, so the
// marker is the answer to "is this a group", not decoration on every box.
function marker(n) {
  if (!n.hasChildren) return ''
  return n.open ? '▾' : '▸'
}

// The open set, changed by one node. Closing removes that id and nothing else:
// what was open below it stays in the set, so opening it again shows what the
// reader had opened before rather than a collapsed subtree.
function toggleOpen(open, id) {
  if (open[id] === true) delete open[id]
  else open[id] = true
  return open
}

// Every node that can be opened, deepest included - what "open all groups" sets
// the state to, and the complement of the empty set "close all groups" leaves.
function groupIds(data) {
  const out = []
  const walk = (n) => {
    if (n.children.length === 0) return
    out.push(n.id)
    n.children.forEach(walk)
  }
  treeOf(data).children.forEach(walk)
  return out
}

// The arrows one node answers for: the ones that leave it and the ones that
// arrive at it. It is computed from the laid-out edges rather than read off the
// drawing, so the set is the same whether anything has been drawn yet or not. A
// node no arrow touches answers with the empty set, which is a fact about the
// module - it depends on nothing outside itself and nothing outside it depends
// on it - rather than a failure to find anything.
function edgesAt(edges, id) {
  return edges.filter((e) => e.from === id || e.to === id)
}

// What the panel says while a node is highlighted: one line per arrow, naming
// which way the dependency runs, how many module imports are behind it, which
// kinds they are and how many of each, and the rule where one names the edge.
// This is the count that used to sit beside the lane, asked for instead of
// permanent. A node with no arrows says so in a line of its own: an empty panel
// reads as a page that failed rather than as an answer.
function edgeLines(edges, id) {
  const mine = edgesAt(edges, id)
  if (mine.length === 0) return ['no arrows: nothing here imports across a boundary, and nothing imports it']
  return mine.map((e) => {
    const out = e.from === id
    const way = out ? 'imports ' : 'imported by '
    const rule = e.rule ? ' - ' + e.rule + (e.state === 'inherited' ? ' (inherited)' : '') : ''
    return way + (out ? e.toLabel : e.fromLabel) + ': ' + e.weight + ' module edges' +
      (e.kindLabel ? ' (' + e.kindLabel + ')' : '') + rule
  })
}

// The page's own script, written here and inlined by `html` through
// `toString()`. It is never called in node: it exists to be read as source, and
// it may touch nothing this module holds beyond the functions `fns` inlines
// beside it, which travel together.
function draw() {
  const data = JSON.parse(document.getElementById('cast-data').textContent)
  const svg = document.getElementById('graph')
  const panel = document.getElementById('sites')
  const NS = 'http://www.w3.org/2000/svg'
  const open = {}
  for (const id of data.open || []) open[id] = true
  const el = (name, attrs, text) => {
    const n = document.createElementNS(NS, name)
    for (const k of Object.keys(attrs)) n.setAttribute(k, attrs[k])
    if (text !== undefined) n.textContent = text
    return n
  }
  const sites = (e) => {
    panel.textContent = ''
    const h = document.createElement('h3')
    h.textContent = e.weight + ' module edges' + (e.kindLabel ? ' (' + e.kindLabel + ')' : '') + (e.rule ? ' - ' + e.label : '')
    panel.appendChild(h)
    const ul = document.createElement('ul')
    for (const s of e.sites) {
      const li = document.createElement('li')
      li.textContent = s.file + ':' + s.line + ' -> ' + s.to + ' (' + s.kind + ')' + (s.rule ? ' ' + s.rule : '')
      ul.appendChild(li)
    }
    panel.appendChild(ul)
  }
  // The highlight is state of the drawing, never of the data: the node being
  // pointed at, the arrows it answers for left exactly as they are drawn at
  // rest, and every other arrow faded. Fading is all it does - it subtracts from
  // the others rather than restyling the ones it names, so an arrow's colour,
  // width, dash and head still say what they said before.
  let laid = null
  let arrows = []
  let held = null
  const highlight = (id, label) => {
    held = id
    const mine = new Set(edgesAt(laid.edges, id))
    for (const a of arrows) a.line.classList.toggle('dim', !mine.has(a.e))
    panel.textContent = ''
    const h = document.createElement('h3')
    h.textContent = label
    panel.appendChild(h)
    const ul = document.createElement('ul')
    for (const line of edgeLines(laid.edges, id)) {
      const li = document.createElement('li')
      li.textContent = line
      ul.appendChild(li)
    }
    panel.appendChild(ul)
  }
  // Nothing highlighted is not something to undo: leaving a node the reader
  // never highlighted would otherwise wipe the list of imports they pressed an
  // arrow for.
  const unhighlight = () => {
    if (held === null) return
    held = null
    for (const a of arrows) a.line.classList.remove('dim')
    panel.textContent = ''
  }
  // A finger has no hover, so the press itself is timed: `HOLD` elapsed on one
  // spot is the question, anything shorter or further is the tap it always was.
  const HOLD = 450
  const SLOP = 10
  let press = null
  let suppress = false
  const cancelPress = () => {
    if (press) clearTimeout(press.timer)
    press = null
  }
  // Pressing anything that is not the highlighted node ends the highlight: on a
  // phone there is no pointer to move away, so this is the way back. It ends on
  // the release and not on the touch, because the touch that scrolls the page is
  // how a phone reaches the panel: clearing at the start of the gesture takes the
  // numbers away in the moment the reader scrolls to them. So the touch only
  // proposes the end, and a gesture that travels or that the browser takes over
  // for a scroll withdraws it.
  let away = null
  const cancelAway = () => { away = null }
  document.addEventListener('pointerdown', (ev) => {
    if (held === null) return
    const g = ev.target && ev.target.closest ? ev.target.closest('.node') : null
    away = (!g || g.id !== held) ? { x: ev.clientX, y: ev.clientY, held } : null
  })
  document.addEventListener('pointermove', (ev) => {
    if (away && (Math.abs(ev.clientX - away.x) > SLOP || Math.abs(ev.clientY - away.y) > SLOP)) cancelAway()
  })
  document.addEventListener('pointercancel', cancelAway)
  // Only where the highlight is still the one that press was away from: a long
  // press on another node moves the highlight itself, and the release that ends
  // that press must not take the node it just asked for away.
  document.addEventListener('pointerup', () => {
    if (away && away.held === held) unhighlight()
    cancelAway()
  })
  const toggle = (id) => {
    toggleOpen(open, id)
    panel.textContent = ''
    render()
  }
  // The two controls over the whole page: close every group, or open every one
  // that has children. Both write the same state a header writes.
  const setAll = (ids) => {
    for (const k of Object.keys(open)) delete open[k]
    for (const id of ids) open[id] = true
    panel.textContent = ''
    render()
  }
  document.getElementById('collapse-all').addEventListener('click', () => setAll([]))
  document.getElementById('expand-all').addEventListener('click', () => setAll(groupIds(data)))
  function render() {
    const l = layoutTree(viewTree(data, Object.keys(open)))
    const M = l.metrics
    // Every arrow is drawn again from nothing, so no faded one survives a
    // render: the highlight ends when the drawing it described does.
    unhighlight()
    cancelPress()
    cancelAway()
    laid = l
    arrows = []
    svg.textContent = ''
    svg.setAttribute('viewBox', '0 0 ' + l.width + ' ' + l.height)
    // The drawing keeps its own size in css pixels and the container around it
    // scrolls. Fitting it to the screen instead would shrink a deep tree until
    // no label and no target survives it.
    svg.setAttribute('width', l.width)
    svg.setAttribute('height', l.height)
    // A box is drawn before the children it holds, so an open node keeps its own
    // outline and they sit inside it. The click stops there: an inner box closes
    // itself, not the ancestor whose rectangle is behind it.
    const box = (n) => {
      const g = el('g', { class: 'node ' + n.kind + (n.open ? ' open' : ' closed'), id: n.id })
      g.appendChild(el('rect', { x: n.x, y: n.y, width: n.w, height: n.h, rx: 6 }))
      // The header carries the marker and the label, and it alone toggles: the
      // rest of an open box is where the children sit, and a press there is a
      // press on nothing.
      const head = el('g', { class: 'head' })
      head.appendChild(el('rect', { x: n.hx, y: n.hy, width: n.hw, height: n.hh, class: 'hit' }))
      const m = marker(n)
      const ty = n.hy + n.hh / 2 + 5
      if (m) head.appendChild(el('text', { x: n.hx + 10, y: ty, class: 'marker' }, m))
      head.appendChild(el('text', { x: n.hx + (m ? 28 : 10), y: ty }, n.label))
      // A mouse points and the node answers. `pointerenter` is bound for a mouse
      // alone: a touch screen fires it on the first contact, so an unguarded
      // binding highlights on every tap a phone makes.
      head.addEventListener('pointerenter', (ev) => { if (ev.pointerType === 'mouse') highlight(n.id, n.label) })
      head.addEventListener('pointerleave', (ev) => { if (ev.pointerType === 'mouse') unhighlight() })
      // A finger asks by holding. The timer elapses and the node highlights and
      // the click the release brings is eaten, so a press that highlights never
      // also opens the group; a release, a cancel or a move beyond the slop
      // before it elapses leaves the tap a tap.
      head.addEventListener('pointerdown', (ev) => {
        if (ev.pointerType === 'mouse') return
        suppress = false
        cancelPress()
        press = {
          x: ev.clientX,
          y: ev.clientY,
          timer: setTimeout(() => { press = null; suppress = true; highlight(n.id, n.label) }, HOLD),
        }
      })
      head.addEventListener('pointermove', (ev) => {
        if (press && (Math.abs(ev.clientX - press.x) > SLOP || Math.abs(ev.clientY - press.y) > SLOP)) cancelPress()
      })
      // A release ends the press, never the highlight: a finger that lifted is a
      // finger off the screen, and clearing here would take the numbers away in
      // the moment the reader looks at them. The press elsewhere clears it.
      head.addEventListener('pointerup', (ev) => { if (ev.pointerType !== 'mouse') cancelPress() })
      head.addEventListener('pointercancel', (ev) => { if (ev.pointerType !== 'mouse') cancelPress() })
      if (n.hasChildren) {
        head.setAttribute('role', 'button')
        head.setAttribute('tabindex', '0')
        head.setAttribute('aria-expanded', n.open === true ? 'true' : 'false')
        head.addEventListener('click', (ev) => {
          // The click a release brings after a press that highlighted is eaten
          // once: what asked for the numbers never also opens the group.
          if (suppress) { suppress = false; ev.stopPropagation(); return }
          ev.stopPropagation(); toggle(n.id)
        })
      }
      g.appendChild(head)
      svg.appendChild(g)
      for (const c of n.children) box(c)
    }
    for (const n of l.nodes) box(n)
    // Boxes and bare curves, and nothing else. What an arrow carries is read by
    // pressing it or by pointing at a node it joins, so no digits are drawn
    // beside it and no arrow needs a backing to stay legible. There is no head
    // either: the side the curve runs on is what says which way the dependency
    // runs, and it says it on a drawing too crowded for a hundred heads.
    for (const e of l.edges) {
      const d = 'M ' + e.x1 + ' ' + e.y1 + ' C ' + e.mx + ' ' + e.y1 + ' ' + e.mx + ' ' + e.y2 + ' ' + e.x2 + ' ' + e.y2
      const line = el('path', {
        d, fill: 'none', stroke: 'var(--edge-' + e.tone + ')', 'stroke-width': e.state ? 3 : 1.5,
        'stroke-dasharray': e.state === 'inherited' ? '6 4' : 'none',
        class: 'edge',
      })
      line.addEventListener('click', () => sites(e))
      svg.appendChild(line)
      // A line a pen can hit is thinner than a finger: the arrow's own target is
      // an invisible stroke `TAP` wide over the same curve.
      const grab = el('path', { d, fill: 'none', stroke: 'transparent', 'stroke-width': M.TAP, class: 'edge grab' })
      grab.addEventListener('click', () => sites(e))
      svg.appendChild(grab)
      arrows.push({ e, line })
    }
  }
  render()
}

function mermaid(graph, rules, expand, checkRules, baseline) {
  const data = viewData(graph, rules, checkRules, baseline)
  const all = data.layers.map((l) => l.name)
  if (expand && !all.includes(expand)) die(`no layer ${expand}: the layers are ${all.join(', ')}`)
  const view = viewAt(data, expand)
  const lines = ['graph LR']
  for (const l of data.layers) {
    if (l.name === expand) {
      lines.push(`  subgraph ${nodeId('L_', l.name)}["${l.name}"]`)
      for (const n of view.nodes) if (n.layer === l.name) lines.push(`    ${n.id}["${n.label}"]`)
      lines.push('  end')
    } else {
      const n = view.nodes.find((x) => x.layer === l.name && !x.module)
      lines.push(`  ${n.id}["${n.label}"]`)
    }
  }
  view.edges.forEach((e) => lines.push(`  ${e.from} -->|${e.label}| ${e.to}`))
  // Only a flagged arrow is styled: a graph nobody has written a rule for prints
  // exactly what it printed before.
  view.edges.forEach((e, i) => {
    if (e.state) lines.push(`  linkStyle ${i} stroke:${e.color},stroke-width:2px`)
  })
  return lines.join('\n')
}

// `touch-action:manipulation` is what makes one press act once: without it a
// phone waits for a second tap before it believes the first, and the wait is a
// zoom. Nothing here reveals a control on `:hover` - there is no hover on a
// phone, so a control that needs one does not exist there.
// The page is an instrument, not a document: a project's name in the type of a
// path, the counts as a panel that says at a glance which of them should have
// been zero, and one drawing under them. Two faces carry it - a sans for the
// chrome, a mono everywhere the page shows something the project itself named:
// the project, a module, a file and line, a count. No face is fetched: the page
// loads nothing at view time, which rules a webfont out and leaves the stacks
// below, each ending in a family every platform has.
//
// Every colour is a custom property on bare `:root`, so one sheet answers three
// ways of asking for a theme: the page's own light default, a viewer that only
// reports `prefers-color-scheme`, and a host that stamps `data-theme` on the
// root element. A colour defined only inside one of those blocks is missing in
// the other two, so none is.
const THEME_LIGHT = [
  'color-scheme:light',
  '--bg:#f7f9fb', '--surface:#ffffff', '--fg:#141a21', '--muted:#5d6b7a', '--line:#e3e9ef',
  '--accent:#2f5d8c',
  '--bad:#b3261e', '--bad-bg:#fdf1f0', '--warn:#8a5a00', '--warn-bg:#fdf6e7',
  '--btn-bg:#ffffff', '--btn-line:#d3dbe3',
  // Depth reads as recession, not as three unrelated hues: one family, the layer
  // carrying the accent and each level inside it quieter than the one holding it.
  '--node-bg:#e8eff8', '--node-line:#2f5d8c',
  '--folder-bg:#eff3f7', '--folder-line:#93a4b8',
  '--file-bg:#f7f9fb', '--file-line:#c3ccd7',
  '--edge-plain:#666666', '--edge-inherited:#888888',
  '--edge-warn:#e08b00', '--edge-error:#d32f2f',
].join(';')
const THEME_DARK = [
  'color-scheme:dark',
  '--bg:#0e1216', '--surface:#161c23', '--fg:#e7ecf1', '--muted:#96a3b2', '--line:#242d37',
  '--accent:#7fa9d8',
  '--bad:#ff8a80', '--bad-bg:#2a1618', '--warn:#f0b45a', '--warn-bg:#2a2113',
  '--btn-bg:#1c232b', '--btn-line:#313b46',
  '--node-bg:#18242f', '--node-line:#7fa9d8',
  '--folder-bg:#171d25', '--folder-line:#5a6979',
  '--file-bg:#111721', '--file-line:#3a4552',
  '--edge-plain:#9aa0a6', '--edge-inherited:#6e747a',
  '--edge-warn:#f0a830', '--edge-error:#ff6b6b',
].join(';')

const SANS = 'ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif'
const MONO = 'ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace'
const LABEL = 'font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted)'

const PAGE_CSS = [
  `:root{${THEME_LIGHT}}`,
  `@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){${THEME_DARK}}}`,
  `:root[data-theme="dark"]{${THEME_DARK}}`,
  '*{box-sizing:border-box}',
  'html,body{max-width:100%;overflow-x:hidden}',
  // The ground is painted, never inherited: a transparent body borrows the
  // background of whatever embeds the page, and a drawing built for one theme
  // lands on the other.
  `body{font:16px/1.5 ${SANS};margin:0;padding:clamp(16px,4vw,40px);color:var(--fg);background:var(--bg);touch-action:manipulation}`,
  // Every gap is the layout's, never a margin's: two of those collapse into one
  // and the spacing stops being the number it says it is.
  '.page{max-width:1120px;margin:0 auto;display:flex;flex-direction:column;gap:28px}',
  'section{display:flex;flex-direction:column;gap:10px}',
  // The project is a directory the reader knows by its path, so it is set in the
  // face a path is set in.
  `h1{margin:0;font:600 clamp(26px,4vw,38px)/1.15 ${MONO};letter-spacing:-.01em;text-wrap:balance;overflow-wrap:anywhere}`,
  `h2{margin:0;${LABEL};font-weight:600}`,
  `.eyebrow{margin:0;${LABEL}}`,
  // Each cell carries its own outline and the grid only spaces them: a track the
  // last row leaves empty then shows the page's own ground, not a panel with a
  // hole in it.
  '.stats{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(132px,1fr));gap:8px}',
  '.stat{display:flex;flex-direction:column;gap:3px;padding:10px 12px;background:var(--surface);border:1px solid var(--line);border-radius:6px}',
  `.stat .k{${LABEL}}`,
  `.stat .v{font:400 21px/1.1 ${MONO};font-variant-numeric:tabular-nums}`,
  // A count that should have been zero says so in its own colour, so the panel
  // is read at a glance and not summed by the reader.
  '.stat.bad{background:var(--bad-bg);border-color:var(--bad)}',
  '.stat.bad .k,.stat.bad .v{color:var(--bad)}',
  '.stat.warn{background:var(--warn-bg);border-color:var(--warn)}',
  '.stat.warn .k,.stat.warn .v{color:var(--warn)}',
  '#controls{display:flex;flex-wrap:wrap;gap:8px;margin:0}',
  // Nothing on this page answers a hover: there is none on a phone, so a state
  // only a pointer can reach is a state half the readers never see.
  'button{font:inherit;min-height:44px;min-width:44px;padding:0 14px;cursor:pointer;touch-action:manipulation;color:var(--fg);background:var(--btn-bg);border:1px solid var(--btn-line);border-radius:6px}',
  'button:focus-visible{outline:2px solid var(--accent);outline-offset:2px}',
  // The graph scrolls inside its own box. It is never scaled to fit: a tree
  // deep enough to need this is a tree too small to read once it has been.
  '#graph-scroll{overflow-x:auto;max-width:100%;width:max-content;border:1px solid var(--line);background:var(--surface);border-radius:6px}',
  '#graph{display:block;touch-action:manipulation}',
  '.node rect{fill:var(--node-bg);stroke:var(--node-line)}',
  '.node.folder rect{fill:var(--folder-bg);stroke:var(--folder-line)}',
  '.node.file rect{fill:var(--file-bg);stroke:var(--file-line)}',
  '.node.open>rect{fill:none;stroke-dasharray:4 3}',
  // svg text carries its own `fill` and never the `color` around it: without
  // this the labels stay black wherever the ground goes dark. A node's label is
  // a file name, so it is set in the mono; 14px keeps the longest of them inside
  // a box whose width is fixed, never measured.
  `.node text{font:14px ${MONO};pointer-events:none;fill:var(--fg)}`,
  '.node .head{cursor:pointer}',
  // The target itself: painted with nothing, pressed like anything else.
  '.hit,.node .hit{fill:transparent;pointer-events:all}',
  '.edge{cursor:pointer}',
  '.edge.grab{pointer-events:stroke}',
  // The one thing a highlight does to an arrow it did not name: fade it. The
  // arrows it does name are left alone, so their colour, width and dash are the
  // ones they carry at rest.
  '.edge.dim{opacity:.15}',
  // Nothing was pressed yet, so the panel is not a box of air.
  '#sites:empty{display:none}',
  '#sites{background:var(--surface);border:1px solid var(--line);border-radius:6px;padding:14px 16px}',
  '#sites h3{margin:0 0 8px;font-size:15px;font-weight:600}',
  '#sites ul{margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px}',
  `#sites li{font-family:${MONO};font-size:13px;overflow-wrap:anywhere;color:var(--muted)}`,
  '.chips{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:8px}',
  `.chip{font:13px ${MONO};padding:5px 10px;border:1px solid var(--line);border-radius:4px;background:var(--surface)}`,
  '.chip b{font-weight:400;color:var(--muted)}',
  // What the drawing answers to, kept where it does not open the page: shut, at
  // the foot, for the reader who wants it.
  '.legend{border-top:1px solid var(--line);padding-top:16px;color:var(--muted);font-size:14px}',
  `.legend summary{cursor:pointer;${LABEL}}`,
  '.legend summary:focus-visible{outline:2px solid var(--accent);outline-offset:2px}',
  '.legend p{margin:10px 0 0;max-width:66ch}',
].join('')

// Self-contained on purpose: the data, the script and the style are in the file
// and nothing is fetched at view time. What the page draws it computes from the
// embedded description, through the functions the commands use. It draws that
// graph once: the mermaid source is `render --mermaid`, for an issue or a
// document, and repeating it below a drawing that opens every node said less
// than the drawing already did.
//
// `fragment` drops the document around that content and nothing else. A host
// that supplies its own `<!doctype>`, `<head>` and `<body>` - an artifact page
// is one - rejects a second set, so the same style, drawing and script are
// written with no skeleton of their own. The `<title>` stays first: it is what
// names the page, and a host that reads one reads only the head of the file.
function html(graph, rules, expand, checkRules, baseline, fragment) {
  const data = viewData(graph, rules, checkRules, baseline)
  const all = data.layers.map((l) => l.name)
  if (expand && !all.includes(expand)) die(`no layer ${expand}: the layers are ${all.join(', ')}`)
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  const c = data.counts
  // The two panels are the two commands: what `cast report` counts about the
  // graph, and what `cast check` counts against the rules. A count that is a
  // finding rather than a size carries its severity, and only where it is not
  // zero - a project with nothing wrong shows no colour at all.
  const stat = (k, v, tone) =>
    `<li class="stat${tone && v > 0 ? ' ' + tone : ''}"><span class="k">${esc(k)}</span><span class="v">${v}</span></li>`
  const graphStats = [
    stat('modules', c.modules), stat('edges', c.edges), stat('module edges', c.moduleEdges),
    stat('layers', c.layers), stat('unassigned', c.unassigned, 'warn'),
    stat('unresolved', c.unresolved, 'bad'), stat('opaque', c.opaque, 'warn'),
    stat('cycles', c.cycles, 'bad'),
  ].join('\n')
  const ruleStats = [
    stat('rules', c.rules), stat('violations', c.violations, 'bad'),
    stat('errors', c.errors, 'bad'), stat('baselined', c.baselined, 'warn'),
  ].join('\n')
  const layers = all
    .map((l) => `<li class="chip">${esc(l)} <b>${data.layers.find((x) => x.name === l).modules.length}</b></li>`)
    .join('\n')
  // The page is named after the project it read, because that is the one thing
  // that tells two of these pages apart in a list of them.
  const project = String(graph.root || '').replace(/[\\/]+$/, '').split(/[\\/]/).pop()
  const title = project ? `${project} module graph` : 'module graph'
  // `</` inside the JSON would end the script element early, whatever it means
  // to JSON: the escape is the only thing between the data and a broken page.
  // `--expand <layer>` opens that layer's node, the one state the command can
  // name; every deeper node is opened by clicking it.
  const embedded = JSON.stringify({ ...data, open: expand ? [treeId(expand)] : [] }).replace(/</g, '\\u003c')
  const fns = [treeId, treeOf, viewTree, layoutTree, marker, toggleOpen, groupIds, edgesAt, edgeLines, draw]
  const script = fns.map((f) => f.toString()).join('\n\n') + '\ndraw()\n'
  // The drawing opens the page: nothing is introduced, because the counts above
  // it and the controls beside it are what an introduction would have said. What
  // is left - which press does what - is shut at the foot, for the reader who
  // goes looking.
  const content = [
    '<div class="page">',
    '<header class="head">',
    '<p class="eyebrow">module graph</p>',
    `<h1>${esc(project || 'cast')}</h1>`,
    '</header>',
    '<section>',
    '<h2>graph</h2>',
    `<ul class="stats" id="counts">\n${graphStats}\n</ul>`,
    '</section>',
    '<section>',
    '<h2>rules</h2>',
    `<ul class="stats" id="rule-counts">\n${ruleStats}\n</ul>`,
    '</section>',
    '<section>',
    '<p id="controls"><button type="button" id="collapse-all">close all groups</button><button type="button" id="expand-all">open all groups</button></p>',
    '<div id="graph-scroll"><svg id="graph" role="img" aria-label="the module graph"></svg></div>',
    '<div id="sites"></div>',
    '</section>',
    '<section>',
    '<h2>layers</h2>',
    `<ul class="chips" id="layers">\n${layers}\n</ul>`,
    '</section>',
    '<details class="legend">',
    '<summary>reading the graph</summary>',
    '<p>A node marked ▸ is a closed group and one marked ▾ is an open one. Press a group’s header - its marker or its label - to open or close it, an arrow to list the imports behind it. An arrow runs to the right of the boxes where it imports something further down, to the left where it imports something further up. To ask for the numbers, point at a node with the mouse or press and hold it on a touch screen: its own arrows stay while the rest fade, and the panel says how many imports run each way, of which kinds - value, type or dynamic - and under which rule.</p>',
    '</details>',
    '</div>',
    `<script id="cast-data" type="application/json">${embedded}</script>`,
    `<script>\n${script}</script>`,
  ]
  if (fragment) {
    return [`<title>${esc(title)}</title>`, `<style>${PAGE_CSS}</style>`, ...content, ''].join('\n')
  }
  return [
    '<!doctype html>',
    '<html lang="en">',
    // Without this a phone lays the page out at a desktop width and scales the
    // result down, which is how a 44 pixel target becomes a 15 pixel one.
    `<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${esc(title)}</title>`,
    `<style>${PAGE_CSS}</style>`,
    '</head>',
    '<body>',
    ...content,
    '</body>',
    '</html>',
    '',
  ].join('\n')
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
    // Comments are blanked before any pattern runs, so a commented-out import
    // and a jsdoc annotation naming a module make no edge.
    const text = mask(ctx.read(id) || '', adapter.comments)
    const edges = []
    // An import whose target is not a literal string is met here too: the
    // adapter's `opaque` patterns say which text that is, and the edge is kept
    // with the expression as its target. Passed over, it would leave a graph
    // that is missing edges reading as a complete one.
    const found = [
      ...imports(text, adapter).map((i) => ({ ...i, opaque: false })),
      ...imports(text, { patterns: adapter.opaque || [] }).map((i) => ({ ...i, opaque: true })),
    ].sort((a, b) => a.line - b.line || (a.target < b.target ? -1 : 1))
    for (const imp of found) {
      const answer = imp.opaque
        ? null
        : adapter.resolve(imp.target, id, { ...ctx, state: adapter.state }) || null
      // The site travels with the edge: without the file and the line, a report
      // names a problem nobody can open.
      const edge = {
        target: imp.target,
        kind: imp.kind,
        file: id,
        line: imp.line,
        to: null,
        resolution: imp.opaque ? 'opaque' : 'unresolved',
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

const RESOLUTIONS = ['module', 'external', 'unresolved', 'opaque']

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
  // What that count counts: every import met, whatever became of it. Every
  // narrower count in cast is labelled `module edges`, and this line is where
  // the difference between the two is readable.
  const byResolution = (r) => edges.filter((e) => e.resolution === r)
  out.push(
    '  ' + RESOLUTIONS.map((r) => `${r} ${byResolution(r).length}`).join(', ')
  )

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

  // An import cast cannot read is neither resolved nor unresolved: nothing was
  // looked up. Counted and named all the same - the edges it stands for are
  // missing from every count below, and a report that passed over it would say
  // the graph has them.
  const opaque = byResolution('opaque')
  out.push(`opaque ${opaque.length}`)
  for (const e of opaque) out.push(`  ${e.file}:${e.line} ${e.target} (${e.kind})`)

  const found = cycles(graph)
  out.push(`cycles ${found.length}`)
  for (const c of found) out.push(`  cycle: ${c.join(' -> ')}`)
  return out.join('\n')
}

// The graph is derived state, and derived state does not belong in the tree it
// describes. Written into `<root>/.cast/` it had to be gitignored by every
// project that ran cast, and every agent that scanned one left a file behind in
// a checkout it was told not to touch. It goes to a scratch directory under the
// system temp instead, keyed by the root: `cast scan` and the six commands that
// read the graph back derive the same path from the same `--root`, so neither
// has to be told where it is, and two roots never share a file.
//
// `CAST_GRAPH` names the file outright, for a caller with a scratch directory of
// its own - an agent handed one in its task. An environment variable rather than
// a flag because the whole point is that scan and the command reading its graph
// agree: exported once it holds for every call, where a flag is one more thing
// to repeat on each and to forget on one.
function graphFile(root) {
  const named = process.env.CAST_GRAPH
  if (named) return path.resolve(named)
  const key = crypto.createHash('sha1').update(root).digest('hex').slice(0, 12)
  return path.join(os.tmpdir(), 'cast', `${path.basename(root) || 'root'}-${key}`, 'graph.json')
}

function readGraph(out) {
  try {
    return JSON.parse(fs.readFileSync(out, 'utf8'))
  } catch {
    die(`no graph at ${out}: run cast scan first`)
  }
}

// --- rules ------------------------------------------------------------------

// Rules are read at check time from `<root>/.cast/rules.json`, the same contract
// as layers.json: never baked into the graph, so a rule can be added, tightened
// or dropped without a rescan. `forbidden` names an edge that must not exist;
// `allowed` is the exception list - an edge a forbidden rule caught is dropped
// where an allowed rule claims the same edge.
//
// Each rule carries `name`, `severity`, `from`, `to` and `kinds`. A side is a
// layer name where one is declared, and a path glob otherwise, so a rule can be
// written between two layers or between two files with no layer of their own.
const RULE_KEYS = ['name', 'severity', 'from', 'to', 'kinds']

function side(spec, names) {
  if (typeof spec !== 'string' || !spec) return null
  // A declared layer name wins over a path of the same spelling: layers are what
  // rules are normally written between, and a layer name is rarely a valid path.
  if (names.includes(spec) || spec === UNASSIGNED) return { layer: spec }
  return { re: globToRe(spec) }
}

// A side that is there but is not a layer name or a path glob is its own error:
// told it carries no from, the author looks for a key that is in the file. The
// message names the shape that was expected instead.
function sideShape(r, key, at) {
  const v = r[key]
  if (v === undefined || v === null) die(`${at} (${r.name}) carries no ${key}`)
  if (typeof v !== 'string' || !v)
    die(`${at} (${r.name}) has ${key} ${JSON.stringify(v)}, not a layer name or a path glob`)
}

// One rule object, validated. Every path into the evaluator goes through this,
// so a rule is read the same way wherever it is written down, unknown attribute
// report included.
function readRule(r, at, names, notEvaluated) {
  if (!r || typeof r !== 'object' || Array.isArray(r)) die(`${at} is not a rule object`)
  if (typeof r.name !== 'string' || !r.name) die(`${at} carries no name`)
  sideShape(r, 'from', at)
  sideShape(r, 'to', at)
  const from = side(r.from, names)
  const to = side(r.to, names)
  const severity = r.severity === undefined ? 'error' : r.severity
  if (severity !== 'error' && severity !== 'warn')
    die(`${at} (${r.name}) has severity ${JSON.stringify(r.severity)}, not error or warn`)
  let kinds = null
  if (r.kinds !== undefined) {
    if (!Array.isArray(r.kinds) || r.kinds.some((k) => typeof k !== 'string'))
      die(`${at} (${r.name}) has kinds that are not a list of edge kinds`)
    kinds = r.kinds
  }
  // An attribute this evaluator cannot decide is named, never quietly passed:
  // a green check must not stand for a rule nobody evaluated.
  for (const k of Object.keys(r)) if (!RULE_KEYS.includes(k)) notEvaluated.push(`${r.name}: ${k}`)
  return { name: r.name, severity, kinds, from, to, fromSpec: r.from, toSpec: r.to }
}

function readRules(root, names) {
  const file = path.join(root, '.cast', 'rules.json')
  let raw
  try {
    raw = fs.readFileSync(file, 'utf8')
  } catch {
    return null
  }
  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    die(`${file} is not valid JSON: ${e.message}`)
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed))
    die(`${file} is not an object holding forbidden and allowed rules`)
  const notEvaluated = []
  const read = (key) => {
    const list = parsed[key]
    if (list === undefined) return []
    if (!Array.isArray(list)) die(`${file}: ${key} is not an array of rules`)
    return list.map((r, i) => readRule(r, `${file}: ${key}[${i}]`, names, notEvaluated))
  }
  const forbidden = read('forbidden')
  const allowed = read('allowed')
  return { forbidden, allowed, notEvaluated }
}

function sideHits(s, id, of) {
  return s.layer !== undefined ? of.get(id) === s.layer : s.re.test(id)
}

function hits(rule, fromId, edge, of) {
  if (rule.kinds && !rule.kinds.includes(edge.kind)) return false
  return sideHits(rule.from, fromId, of) && sideHits(rule.to, edge.to, of)
}

// Every resolved module edge is evaluated, including the ones inside a single
// layer. The check reads the module graph and never the aggregate the renderer
// draws, where an intra-layer edge has no arrow at all.
function violations(graph, of, rules) {
  const out = []
  for (const m of graph.modules) {
    for (const e of m.edges) {
      if (e.resolution !== 'module') continue
      rules.forbidden.forEach((r, ri) => {
        if (!hits(r, m.id, e, of)) return
        if (rules.allowed.some((a) => hits(a, m.id, e, of))) return
        out.push({
          ri,
          rule: r.name,
          severity: r.severity,
          file: e.file,
          line: e.line,
          to: e.to,
          kind: e.kind,
          edge: `${of.get(m.id)} -> ${of.get(e.to)}`,
        })
      })
    }
  }
  return out.sort((a, b) => a.ri - b.ri || (a.file < b.file ? -1 : a.file > b.file ? 1 : a.line - b.line))
}

const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`

function moduleEdges(graph) {
  return graph.modules.reduce((n, m) => n + m.edges.filter((e) => e.resolution === 'module').length, 0)
}

// --- baseline ---------------------------------------------------------------

// The baseline is the violations a project inherited: listed, they leave the
// check green, so a rule can be turned on before the code obeys it. A key is
// the rule, the file, the module imported and the edge kind - never the line,
// which moves every time anything above it is edited and would churn the file.
function baselineKey(v) {
  return [v.rule, v.file, v.to, v.kind].join('\0')
}

const BASELINE_FILE = path.join('.cast', 'baseline.json')

function readBaseline(root) {
  const file = path.join(root, BASELINE_FILE)
  let raw
  try {
    raw = fs.readFileSync(file, 'utf8')
  } catch {
    return null
  }
  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    die(`${file} is not valid JSON: ${e.message}`)
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed) || !Array.isArray(parsed.violations))
    die(`${file} is not an object holding a violations array`)
  const keys = new Set()
  parsed.violations.forEach((v, i) => {
    const at = `${file}: violations[${i}]`
    if (!v || typeof v !== 'object' || Array.isArray(v)) die(`${at} is not a violation object`)
    for (const k of ['rule', 'file', 'to', 'kind'])
      if (typeof v[k] !== 'string' || !v[k]) die(`${at} carries no ${k}`)
    keys.add(baselineKey(v))
  })
  return { file, keys, count: parsed.violations.length }
}

// A held violation is dropped from the listing and from the exit code, and
// counted in the summary: a baseline that hides its own size is a way to stop
// looking at it.
function partition(found, baseline) {
  if (!baseline) return { live: found, held: [] }
  const live = []
  const held = []
  for (const v of found) (baseline.keys.has(baselineKey(v)) ? held : live).push(v)
  return { live, held }
}

// Grouped by rule and then by layer edge, because a violation is fixed one rule
// at a time and read one edge at a time; the site under it is what gets opened.
function group(found, forbidden) {
  const lines = []
  forbidden.forEach((r, ri) => {
    const mine = found.filter((v) => v.ri === ri)
    if (!mine.length) return
    lines.push(`${r.name} (${r.severity}) ${r.fromSpec} -> ${r.toSpec} ${mine.length}`)
    for (const le of [...new Set(mine.map((v) => v.edge))].sort()) {
      const sites = mine.filter((v) => v.edge === le)
      lines.push(`  ${le} ${sites.length}`)
      for (const v of sites) lines.push(`    ${v.file}:${v.line} -> ${v.to} (${v.kind})`)
    }
  })
  return lines
}

function check(graph, of, rules, baseline) {
  const { live: found, held } = partition(violations(graph, of, rules), baseline)
  const edges = moduleEdges(graph)
  const errors = found.filter((v) => v.severity === 'error').length
  const lines = group(found, rules.forbidden)
  for (const n of rules.notEvaluated) lines.push(`not evaluated: ${n}`)
  // The last line is the whole answer where nothing is wrong: one line, the
  // wrapper contract, and it says what was read so a green check is not a silence.
  lines.push(
    `${plural(found.length, 'violation')} (${plural(errors, 'error')}) in ` +
      `${plural(edges, 'module edge')} against ${plural(rules.forbidden.length, 'rule')}` +
      (held.length ? `, ${held.length} baselined` : '')
  )
  return { text: lines.join('\n'), code: errors ? 1 : 0 }
}

// The ratchet: a baseline may replace one that holds at least as many
// violations, never more. Writing is how a violation is accepted, so an
// unguarded write is how a rule quietly stops meaning anything; the refusal is
// the only thing that makes `.cast/baseline.json` a debt that pays down.
function ratchet(root, found) {
  const current = readBaseline(root)
  const had = current ? current.count : null
  if (had !== null && found.length > had)
    return {
      text:
        `refused: ${found.length} violations would replace a baseline of ${had}` +
        ` - a baseline can only shrink`,
      code: 1,
    }
  const body = {
    violations: found.map((v) => ({ rule: v.rule, file: v.file, to: v.to, kind: v.kind })),
  }
  const file = path.join(root, BASELINE_FILE)
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, JSON.stringify(body, null, 2) + '\n')
  return {
    text: `${found.length} violations baselined in ${BASELINE_FILE}` + (had === null ? '' : ` (was ${had})`),
    code: 0,
  }
}

// --- plans ------------------------------------------------------------------

// A plan is a refactoring written down before anyone edits a file: an ordered
// list of operations, read at simulate time from `<root>/.cast/plans/<name>.json`
// like the rules and the layers are, and applied to a copy of the graph. The
// simulation never touches a source file and never rewrites the graph - the whole
// point is to see the answer before the move costs anything.
const PLAN_KEYS = {
  move: ['op', 'module', 'to'],
  split: ['op', 'module', 'into'],
  merge: ['op', 'modules', 'into'],
  invert: ['op', 'from', 'to'],
  redirect: ['op', 'from', 'to', 'via'],
}

function planString(o, key, at) {
  if (typeof o[key] !== 'string' || !o[key]) die(`${at} carries no ${key}`)
  return o[key]
}

function planList(o, key, at) {
  if (!Array.isArray(o[key]) || !o[key].length || o[key].some((s) => typeof s !== 'string' || !s))
    die(`${at}: ${key} is not a list of module ids`)
  return o[key]
}

// One operation, validated. An attribute this simulator cannot apply is a
// die(), never a silent pass: a plan whose answer ignored half of what it says
// is worse than no plan.
function readOperation(o, at) {
  if (!o || typeof o !== 'object' || Array.isArray(o)) die(`${at} is not an operation object`)
  const keys = PLAN_KEYS[o.op]
  if (!keys) die(`${at} has op ${JSON.stringify(o.op)}, not ${Object.keys(PLAN_KEYS).join(', ')}`)
  for (const k of Object.keys(o)) if (!keys.includes(k)) die(`${at} (${o.op}) carries an unknown key ${k}`)
  if (o.op === 'move') return { op: 'move', module: planString(o, 'module', at), to: planString(o, 'to', at) }
  if (o.op === 'merge')
    return { op: 'merge', modules: planList(o, 'modules', at), into: planString(o, 'into', at) }
  if (o.op === 'invert')
    return { op: 'invert', from: planString(o, 'from', at), to: planString(o, 'to', at) }
  if (o.op === 'redirect')
    return {
      op: 'redirect',
      from: planString(o, 'from', at),
      to: planString(o, 'to', at),
      via: planString(o, 'via', at),
    }
  if (!Array.isArray(o.into) || o.into.length < 2) die(`${at}: split needs two or more parts in into`)
  const into = o.into.map((p, i) => {
    const pat = `${at}: into[${i}]`
    if (!p || typeof p !== 'object' || Array.isArray(p)) die(`${pat} is not a part object`)
    for (const k of Object.keys(p))
      if (!['id', 'imports', 'importedBy'].includes(k)) die(`${pat} carries an unknown key ${k}`)
    return {
      id: planString(p, 'id', pat),
      imports: p.imports === undefined ? [] : planList(p, 'imports', pat),
      importedBy: p.importedBy === undefined ? [] : planList(p, 'importedBy', pat),
    }
  })
  return { op: 'split', module: planString(o, 'module', at), into }
}

// A plan is named or it is a path. A bare name is the project's own, read where
// it has always been read - `<root>/.cast/plans/<name>.json`. An argument that
// carries a separator or a `.json` is a path instead, resolved against the
// working directory, so a draft can be simulated out of a scratch directory
// without being written into the checkout first. A plan name is a slug after the
// goal, so the two never collide.
function planFile(root, nameOrPath) {
  if (nameOrPath.endsWith('.json') || nameOrPath.includes('/') || nameOrPath.includes(path.sep))
    return { name: path.basename(nameOrPath, '.json'), file: path.resolve(nameOrPath) }
  return { name: nameOrPath, file: path.join(root, '.cast', 'plans', `${nameOrPath}.json`) }
}

// A path outside the root has no readable relative form: `../../..` names the
// file to nobody. Inside it, the relative one is what the caller typed.
function under(root, file) {
  const rel = path.relative(root, file)
  return rel && !rel.startsWith('..') ? rel : file
}

function readPlan(root, nameOrPath) {
  const { name, file } = planFile(root, nameOrPath)
  let raw
  try {
    raw = fs.readFileSync(file, 'utf8')
  } catch {
    die(`no plan at ${under(root, file)}`)
  }
  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    die(`${file} is not valid JSON: ${e.message}`)
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed) || !Array.isArray(parsed.operations))
    die(`${file} is not an object holding an operations array`)
  // Ordered: operation n is applied to the graph operation n-1 left behind, so a
  // module a move renamed is named by its new id from there on.
  return {
    name,
    file,
    operations: parsed.operations.map((o, i) => readOperation(o, `${file}: operations[${i}]`)),
  }
}

function describe(o) {
  if (o.op === 'move') return `move ${o.module} -> ${o.to}`
  if (o.op === 'merge') return `merge ${o.modules.join(', ')} -> ${o.into}`
  if (o.op === 'invert') return `invert ${o.from} -> ${o.to}`
  if (o.op === 'redirect') return `redirect ${o.from} -> ${o.to} via ${o.via}`
  return `split ${o.module} -> ${o.into.map((p) => p.id).join(', ')}`
}

function findModule(graph, id, at) {
  const m = graph.modules.find((x) => x.id === id)
  if (!m) die(`${at}: no module ${id} in the graph`)
  return m
}

function retarget(graph, was, now) {
  for (const m of graph.modules)
    for (const e of m.edges) if (e.resolution === 'module' && e.to === was) e.to = now
}

// Every operation rewrites the copy in place, and every edge it leaves behind
// names a site in the module that holds it: `file` is that module's id after the
// operation, never the id the module had before it. A site under a name the plan
// has just retired is one nobody can open once the plan is executed. The line is
// the line the import was read at - except on an inverted edge, which is an
// import nobody has written yet and carries line 0.
function resite(m) {
  for (const e of m.edges) e.file = m.id
  return m
}

function apply(graph, o, at) {
  if (o.op === 'move') {
    const m = findModule(graph, o.module, at)
    if (graph.modules.some((x) => x.id === o.to)) die(`${at}: ${o.to} is already a module`)
    m.id = o.to
    resite(m)
    retarget(graph, o.module, o.to)
    return
  }
  if (o.op === 'merge') {
    const parts = o.modules.map((id) => findModule(graph, id, at))
    const gone = new Set(o.modules)
    if (graph.modules.some((x) => x.id === o.into && !gone.has(x.id)))
      die(`${at}: ${o.into} is already a module`)
    const merged = {
      id: o.into,
      adapter: parts[0].adapter,
      // An edge between two merged modules stops being an edge at all: it is a
      // call inside the one module now, which is what merging them means.
      edges: parts.flatMap((p) => p.edges).filter((e) => !(e.resolution === 'module' && gone.has(e.to))),
    }
    resite(merged)
    const at0 = graph.modules.indexOf(parts[0])
    graph.modules = graph.modules.filter((x) => !gone.has(x.id))
    graph.modules.splice(Math.min(at0, graph.modules.length), 0, merged)
    for (const id of o.modules) retarget(graph, id, o.into)
    return
  }
  if (o.op === 'invert') {
    const from = findModule(graph, o.from, at)
    findModule(graph, o.to, at)
    const inverted = from.edges.filter((e) => e.resolution === 'module' && e.to === o.to)
    if (!inverted.length) die(`${at}: no edge ${o.from} -> ${o.to} to invert`)
    from.edges = from.edges.filter((e) => !inverted.includes(e))
    const target = findModule(graph, o.to, at)
    // The direction is what an inversion turns around, and the kind is the one
    // the import has today. The site is the module that would declare it, at
    // line 0: the line the import sits on now belongs to the other file, and
    // carrying it over would name a line of the target nobody wrote it on.
    for (const e of inverted)
      target.edges.push({ ...e, target: o.from, to: o.from, file: o.to, line: 0, resolution: 'module' })
    return
  }
  if (o.op === 'redirect') {
    const from = findModule(graph, o.from, at)
    findModule(graph, o.to, at)
    findModule(graph, o.via, at)
    const rehung = from.edges.filter((e) => e.resolution === 'module' && e.to === o.to)
    if (!rehung.length) die(`${at}: no edge ${o.from} -> ${o.to} to redirect`)
    // The import does not leave `from`, which is the whole difference from an
    // inversion: the file and the line the scan read it at stay real, and the
    // edge keeps its kind. Only what it names changes. `via -> to` is not
    // created here - where the facade does not import `to` already, writing
    // that import is the implementer's work, and a simulation inventing it
    // would report a boundary repaired that nobody has to write.
    for (const e of rehung) {
      e.to = o.via
      e.target = o.via
    }
    return
  }
  const m = findModule(graph, o.module, at)
  for (const p of o.into)
    if (p.id !== o.module && graph.modules.some((x) => x.id === p.id)) die(`${at}: ${p.id} is already a module`)
  const parts = o.into.map((p) => ({ id: p.id, adapter: m.adapter, edges: [] }))
  // An outgoing edge lands on the part that declares it, an incoming one on the
  // part that declares its importer. The first part is the remainder: nothing a
  // plan forgot to place is dropped, which would flatter the plan's own answer.
  for (const e of m.edges) {
    const i = o.into.findIndex((p) => p.imports.includes(e.resolution === 'module' ? e.to : e.target))
    parts[i === -1 ? 0 : i].edges.push({ ...e, file: parts[i === -1 ? 0 : i].id })
  }
  const at0 = graph.modules.indexOf(m)
  graph.modules.splice(at0, 1, ...parts)
  for (const other of graph.modules) {
    if (parts.includes(other)) continue
    for (const e of other.edges) {
      if (e.resolution !== 'module' || e.to !== o.module) continue
      const i = o.into.findIndex((p) => p.importedBy.includes(other.id))
      e.to = parts[i === -1 ? 0 : i].id
    }
  }
}

function simulateGraph(graph, plan) {
  // A copy, never the graph that was read: `cast plan simulate` answers a
  // question, and a question that edits its own subject is not one.
  const after = JSON.parse(JSON.stringify(graph))
  plan.operations.forEach((o, i) => apply(after, o, `${plan.file}: operations[${i}]`))
  return after
}

// Fan-in, fan-out and instability are read at layer altitude, the altitude every
// cast view opens at. An edge inside one layer is neither in nor out of it: the
// numbers are about what a layer depends on and what depends on it.
// I = fan-out / (fan-in + fan-out), Martin's instability - 1 depends on
// everything and nothing depends on it, 0 is depended on and depends on nothing.
function layerMetrics(graph, rules) {
  const { of, names } = assign(graph, rules)
  const all = layerList(graph, of, names)
  const metrics = new Map()
  for (const l of all) metrics.set(l, { in: 0, out: 0 })
  for (const m of graph.modules) {
    const from = of.get(m.id)
    for (const e of m.edges) {
      if (e.resolution !== 'module') continue
      const to = of.get(e.to)
      if (to === from || !metrics.has(from) || !metrics.has(to)) continue
      metrics.get(from).out++
      metrics.get(to).in++
    }
  }
  return metrics
}

const instability = (m) => (m.in + m.out === 0 ? 0 : m.out / (m.in + m.out))

function indent(lines, by) {
  return lines.length ? lines.map((l) => by + l) : [by + 'none']
}

// Before and after, side by side, for every number the plan could move: a
// simulation that printed only the after leaves the reader to remember what the
// project looks like today, and a plan is judged by the difference.
function simulate(graph, after, rules, plan, ruleFile) {
  const lines = [`plan ${plan.name} ${plural(plan.operations.length, 'operation')}`]
  for (const o of plan.operations) lines.push(`  ${describe(o)}`)
  lines.push(`modules ${graph.modules.length} -> ${after.modules.length}`)
  // `module edges`, never `edges`: the simulation moves resolved edges only, and
  // a label shared with the report's every-import count would read as a graph
  // that lost the unresolved ones.
  lines.push(`module edges ${moduleEdges(graph)} -> ${moduleEdges(after)}`)

  const was = cycles(graph)
  const now = cycles(after)
  lines.push(`cycles ${was.length} -> ${now.length}`)
  lines.push('  before')
  lines.push(...indent(was.map((c) => `cycle: ${c.join(' -> ')}`), '    '))
  lines.push('  after')
  lines.push(...indent(now.map((c) => `cycle: ${c.join(' -> ')}`), '    '))

  const mWas = layerMetrics(graph, rules)
  const mNow = layerMetrics(after, rules)
  const zero = { in: 0, out: 0 }
  lines.push('metrics')
  for (const l of [...new Set([...mWas.keys(), ...mNow.keys()])].sort()) {
    const a = mWas.get(l) || zero
    const b = mNow.get(l) || zero
    lines.push(
      `  ${l} fan-in ${a.in} -> ${b.in}, fan-out ${a.out} -> ${b.out}, ` +
        `instability ${instability(a).toFixed(2)} -> ${instability(b).toFixed(2)}`
    )
  }

  if (!ruleFile) {
    lines.push(`violations: no rules: write ${path.join('.cast', 'rules.json')} to check any`)
    return lines.join('\n')
  }
  // The rules are evaluated against both graphs, so a plan that removes a
  // violation is visible as one that does.
  const vWas = violations(graph, assign(graph, rules).of, ruleFile)
  const vNow = violations(after, assign(after, rules).of, ruleFile)
  lines.push(`violations ${vWas.length} -> ${vNow.length}`)
  lines.push('  before')
  lines.push(...indent(group(vWas, ruleFile.forbidden), '    '))
  lines.push('  after')
  lines.push(...indent(group(vNow, ruleFile.forbidden), '    '))
  return lines.join('\n')
}

// --- cli --------------------------------------------------------------------

const USAGE =
  'usage: cast <scan|report|check> [--root <dir>]\n' +
  '       cast plan simulate <name|file> [--root <dir>]\n' +
  '       cast baseline [--update] [--root <dir>]\n' +
  '       cast edges --from <layer> --to <layer> [--root <dir>]\n' +
  '       cast render --mermaid [--expand <layer>] [--plan <name|file>] [--root <dir>]\n' +
  '       cast render --html <file> [--fragment] [--expand <layer>] [--plan <name|file>] [--root <dir>]'

function main(argv) {
  const cmd = argv[0]
  let root = process.cwd()
  let from = null
  let to = null
  let expand = null
  let htmlOut = null
  let fragment = false
  let asMermaid = false
  let update = false
  let planName = null
  // `plan` is the one command with a subcommand and a positional; both are taken
  // before the flag loop, which knows only flags.
  let sub = null
  let ruleArg = null
  let first = 1
  if (cmd === 'plan') {
    sub = argv[1]
    ruleArg = argv[2]
    first = 3
  }
  for (let i = first; i < argv.length; i++) {
    if (argv[i] === '--root' && argv[i + 1]) root = path.resolve(argv[++i])
    else if (cmd === 'baseline' && argv[i] === '--update') update = true
    else if (cmd === 'edges' && argv[i] === '--from' && argv[i + 1]) from = argv[++i]
    else if (cmd === 'edges' && argv[i] === '--to' && argv[i + 1]) to = argv[++i]
    else if (cmd === 'render' && argv[i] === '--mermaid') asMermaid = true
    else if (cmd === 'render' && argv[i] === '--html' && argv[i + 1]) htmlOut = argv[++i]
    else if (cmd === 'render' && argv[i] === '--fragment') fragment = true
    else if (cmd === 'render' && argv[i] === '--expand' && argv[i + 1]) expand = argv[++i]
    else if (cmd === 'render' && argv[i] === '--plan' && argv[i + 1]) planName = argv[++i]
    else die(USAGE)
  }
  // A root that is not a directory is a question about a project that does not
  // exist. It says so here rather than throwing out of the walk, so the caller
  // that mistyped a directory reads which one.
  try {
    if (!fs.statSync(root).isDirectory()) die(`not a directory: ${root}`)
  } catch (e) {
    if (e && e.code === 'ENOENT') die(`no directory at ${root}`)
    throw e
  }
  const out = graphFile(root)

  if (cmd === 'scan') {
    const graph = scan(root)
    fs.mkdirSync(path.dirname(out), { recursive: true })
    fs.writeFileSync(out, JSON.stringify(graph, null, 2) + '\n')
    // The absolute path, because the file is no longer under the root and a
    // path relative to it would climb out through `../..`.
    process.stdout.write(`${graph.modules.length} modules scanned into ${out}\n`)
    return 0
  }
  if (cmd === 'report') {
    const graph = readGraph(out)
    process.stdout.write(report(graph, layerRules(root)) + '\n')
    return 0
  }
  if (cmd === 'check') {
    const graph = readGraph(out)
    const { of, names } = assign(graph, layerRules(root))
    const rules = readRules(root, names)
    // No rules file is not a pass with nothing said: it is the one thing that
    // makes a green check meaningless, so it names itself.
    if (!rules) {
      process.stdout.write(`no rules: write ${path.join('.cast', 'rules.json')} to check any\n`)
      return 0
    }
    const answer = check(graph, of, rules, readBaseline(root))
    process.stdout.write(answer.text + '\n')
    return answer.code
  }
  if (cmd === 'plan') {
    if (sub !== 'simulate' || !ruleArg) die(USAGE)
    const graph = readGraph(out)
    const rules = layerRules(root)
    const plan = readPlan(root, ruleArg)
    const after = simulateGraph(graph, plan)
    // Both assignments contribute the layer names a rule side may be written
    // against, so a rule naming a layer only the plan creates still reads as one.
    const names = [...new Set([...assign(graph, rules).names, ...assign(after, rules).names])]
    process.stdout.write(simulate(graph, after, rules, plan, readRules(root, names)) + '\n')
    // A simulation reports. It writes no file, so there is nothing to fail on.
    return 0
  }
  if (cmd === 'baseline') {
    const graph = readGraph(out)
    const { of, names } = assign(graph, layerRules(root))
    const rules = readRules(root, names)
    if (!rules) {
      process.stdout.write(`no rules: write ${path.join('.cast', 'rules.json')} to check any\n`)
      return 0
    }
    const found = violations(graph, of, rules)
    if (update) {
      const answer = ratchet(root, found)
      process.stdout.write(answer.text + '\n')
      return answer.code
    }
    const current = readBaseline(root)
    if (!current) {
      process.stdout.write(`no baseline: run cast baseline --update to write ${BASELINE_FILE}\n`)
      return 0
    }
    const { live } = partition(found, current)
    // The stale count is the debt already paid: baselined edges the code no
    // longer violates, which the next --update drops.
    const still = new Set(found.map(baselineKey))
    const stale = [...current.keys].filter((k) => !still.has(k)).length
    process.stdout.write(
      `${current.count} baselined, ${live.length} not baselined, ${stale} no longer violated\n`
    )
    return 0
  }
  if (cmd === 'edges') {
    if (!from || !to) die(USAGE)
    const graph = readGraph(out)
    const { of } = assign(graph, layerRules(root))
    const found = layerEdges(graph, of, from, to)
    const lines = [`module edges ${from} -> ${to} ${found.length}`]
    // Each one with its file and its line: a layer edge is only actionable
    // where the imports behind it can be opened.
    for (const e of found) lines.push(`  ${e.file}:${e.line} -> ${e.to} (${e.kind})`)
    process.stdout.write(lines.join('\n') + '\n')
    return 0
  }
  if (cmd === 'render') {
    if (!asMermaid && !htmlOut) die(USAGE)
    // `--fragment` says what a page is written into, so it is an answer only
    // `--html` has a question for.
    if (fragment && !htmlOut) die(USAGE)
    const scanned = readGraph(out)
    // `--plan` renders the graph the plan would leave, never the scanned one:
    // the same picture `cast plan simulate` counts, so a refactoring is looked
    // at before a file is edited. The plan is read and applied before anything
    // is drawn or written, so a plan that cannot be applied exits 2 having
    // produced no page - and the simulated graph is never written back.
    const graph = planName ? simulateGraph(scanned, readPlan(root, planName)) : scanned
    const rules = layerRules(root)
    // The render reads rules.json and the baseline the way `cast check` does, at
    // render time: a view that marked nothing would be a third answer about the
    // same graph.
    const { names } = assign(graph, rules)
    const checkRules = readRules(root, names)
    const baseline = readBaseline(root)
    if (htmlOut) {
      const file = path.resolve(root, htmlOut)
      fs.mkdirSync(path.dirname(file), { recursive: true })
      fs.writeFileSync(file, html(graph, rules, expand, checkRules, baseline, fragment))
      process.stdout.write(`${path.relative(root, file) || file}\n`)
      return 0
    }
    process.stdout.write(mermaid(graph, rules, expand, checkRules, baseline) + '\n')
    return 0
  }
  die(USAGE)
}

if (require.main === module) process.exit(main(process.argv.slice(2)))
module.exports = {
  scan, graphFile, report, cycles, imports, layerRules, layerOf, assign, layerEdges, mermaid, html,
  viewData, viewAt, layout, treeId, treeOf, viewTree, layoutTree, marker, toggleOpen, groupIds,
  edgesAt, edgeLines,
  readRules, violations, check, readBaseline, ratchet,
  readPlan, planFile, simulateGraph, simulate, layerMetrics,
}
