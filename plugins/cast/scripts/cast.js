#!/usr/bin/env node
'use strict'
// cast - the module graph of a project, and what is wrong with it.
//
//   cast scan [--root <dir>]     writes <root>/.cast/graph.json
//   cast report [--root <dir>]   reads it and says what is wrong
//   cast check [--root <dir>]    the rules of <root>/.cast/rules.json, evaluated
//                                against the module graph; exit 1 on an error
//   cast rules preview <rule json> [--root <dir>]
//                                one rule, tried before it is written down: the
//                                module edges it would flag today, per edge
//   cast edges --from <layer> --to <layer> [--root <dir>]
//                                the module edges behind one layer edge
//   cast render --mermaid [--expand <layer>] [--root <dir>]
//   cast render --html <file> [--expand <layer>] [--root <dir>]
//                                the graph at layer altitude, one layer resolved
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

// --- render -----------------------------------------------------------------

// Every view opens at layer altitude: one node per layer, none per module. A
// module only becomes a node where `--expand` asks for its layer, so the picture
// stays readable on a project no reader can hold in their head.
function layerList(graph, of, names) {
  const all = names.slice()
  if (graph.modules.some((m) => of.get(m.id) === UNASSIGNED)) all.push(UNASSIGNED)
  return all
}

// Mermaid ids may not carry `/`, `.` or a space, so the id is sanitised and the
// name travels in the quoted label - the label is what a reader matches on.
function nodeId(prefix, name) {
  return prefix + name.replace(/[^A-Za-z0-9]/g, '_')
}

function mermaid(graph, rules, expand) {
  const { of, names } = assign(graph, rules)
  const all = layerList(graph, of, names)
  if (expand && !all.includes(expand)) die(`no layer ${expand}: the layers are ${all.join(', ')}`)
  const lines = ['graph LR']
  for (const l of all) {
    if (l === expand) {
      lines.push(`  subgraph ${nodeId('L_', l)}["${l}"]`)
      for (const m of graph.modules) if (of.get(m.id) === l) lines.push(`    ${nodeId('M_', m.id)}["${m.id}"]`)
      lines.push('  end')
    } else {
      const n = graph.modules.filter((m) => of.get(m.id) === l).length
      lines.push(`  ${nodeId('L_', l)}["${l} (${n})"]`)
    }
  }
  // The weight is the number of module edges behind the layer edge: without it a
  // layer arrow hides whether it stands for one import or two hundred.
  const weight = new Map()
  const ends = (id) => (of.get(id) === expand ? nodeId('M_', id) : nodeId('L_', of.get(id)))
  for (const m of graph.modules) {
    for (const e of m.edges) {
      if (e.resolution !== 'module') continue
      const a = ends(m.id)
      const b = ends(e.to)
      // An edge inside one collapsed layer has no arrow to draw at this altitude.
      if (a === b) continue
      const k = a + '\0' + b
      weight.set(k, (weight.get(k) || 0) + 1)
    }
  }
  for (const k of [...weight.keys()].sort()) {
    const [a, b] = k.split('\0')
    lines.push(`  ${a} -->|${weight.get(k)}| ${b}`)
  }
  return lines.join('\n')
}

// Self-contained: the page carries the diagram source and the layer names as
// text, and fetches nothing. How it looks is not the claim.
function html(graph, rules, expand) {
  const { of, names } = assign(graph, rules)
  const all = layerList(graph, of, names)
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  const rows = all
    .map((l) => `<li>${esc(l)} (${graph.modules.filter((m) => of.get(m.id) === l).length})</li>`)
    .join('\n')
  return [
    '<!doctype html>',
    '<html lang="en">',
    '<head><meta charset="utf-8"><title>cast</title></head>',
    '<body>',
    '<h1>cast</h1>',
    '<h2>layers</h2>',
    `<ul>\n${rows}\n</ul>`,
    '<h2>graph</h2>',
    `<pre>${esc(mermaid(graph, rules, expand))}</pre>`,
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

// One rule object, validated. Every path into the evaluator goes through this -
// the rules file and `cast rules preview` alike - so a rule tried on the command
// line is read by exactly the rules the file is read by, unknown attribute
// report included.
function readRule(r, at, names, notEvaluated) {
  if (!r || typeof r !== 'object' || Array.isArray(r)) die(`${at} is not a rule object`)
  if (typeof r.name !== 'string' || !r.name) die(`${at} carries no name`)
  const from = side(r.from, names)
  const to = side(r.to, names)
  if (!from) die(`${at} (${r.name}) carries no from`)
  if (!to) die(`${at} (${r.name}) carries no to`)
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

// A rule is tried before it is written down: one rule object, evaluated against
// the scanned graph with the exceptions the project already writes down, so the
// number is what `cast check` would add today and not a number from a project
// with no `allowed` list. The count is edges, never modules - one module with
// three forbidden imports is three imports to move, and a per-module count hides
// two of them. The modules are named beside it, not instead of it.
function preview(graph, of, rule, allowed, notEvaluated) {
  const found = violations(graph, of, { forbidden: [rule], allowed })
  const mods = new Set(found.map((v) => v.file)).size
  const lines = group(found, [rule])
  for (const n of notEvaluated) lines.push(`not evaluated: ${n}`)
  lines.push(
    `${plural(found.length, 'edge')} flagged in ${plural(mods, 'module')} ` +
      `of ${plural(moduleEdges(graph), 'edge')}`
  )
  return lines.join('\n')
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
      `${plural(edges, 'edge')} against ${plural(rules.forbidden.length, 'rule')}` +
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

// --- cli --------------------------------------------------------------------

const USAGE =
  'usage: cast <scan|report|check> [--root <dir>]\n' +
  '       cast rules preview <rule json> [--root <dir>]\n' +
  '       cast baseline [--update] [--root <dir>]\n' +
  '       cast edges --from <layer> --to <layer> [--root <dir>]\n' +
  '       cast render --mermaid [--expand <layer>] [--root <dir>]\n' +
  '       cast render --html <file> [--expand <layer>] [--root <dir>]'

function main(argv) {
  const cmd = argv[0]
  let root = process.cwd()
  let from = null
  let to = null
  let expand = null
  let htmlOut = null
  let asMermaid = false
  let update = false
  // `rules` is the one command with a subcommand and a positional; both are
  // taken before the flag loop, which knows only flags.
  let sub = null
  let ruleArg = null
  let first = 1
  if (cmd === 'rules') {
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
    else if (cmd === 'render' && argv[i] === '--expand' && argv[i + 1]) expand = argv[++i]
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
  if (cmd === 'rules') {
    if (sub !== 'preview' || !ruleArg) die(USAGE)
    let parsed
    try {
      parsed = JSON.parse(ruleArg)
    } catch (e) {
      die(`the rule is not valid JSON: ${e.message}`)
    }
    const graph = readGraph(out)
    const { of, names } = assign(graph, layerRules(root))
    const notEvaluated = []
    const rule = readRule(parsed, 'the rule', names, notEvaluated)
    const written = readRules(root, names)
    process.stdout.write(preview(graph, of, rule, written ? written.allowed : [], notEvaluated) + '\n')
    // A preview reports; it never fails a build. The rule it tried is not one
    // the project has agreed to yet.
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
    const lines = [`edges ${from} -> ${to} ${found.length}`]
    // Each one with its file and its line: a layer edge is only actionable
    // where the imports behind it can be opened.
    for (const e of found) lines.push(`  ${e.file}:${e.line} -> ${e.to} (${e.kind})`)
    process.stdout.write(lines.join('\n') + '\n')
    return 0
  }
  if (cmd === 'render') {
    if (!asMermaid && !htmlOut) die(USAGE)
    const graph = readGraph(out)
    const rules = layerRules(root)
    if (htmlOut) {
      const file = path.resolve(root, htmlOut)
      fs.mkdirSync(path.dirname(file), { recursive: true })
      fs.writeFileSync(file, html(graph, rules, expand))
      process.stdout.write(`${path.relative(root, file) || file}\n`)
      return 0
    }
    process.stdout.write(mermaid(graph, rules, expand) + '\n')
    return 0
  }
  die(USAGE)
}

if (require.main === module) process.exit(main(process.argv.slice(2)))
module.exports = {
  scan, report, cycles, imports, layerRules, layerOf, assign, layerEdges, mermaid, html,
  readRules, violations, check, preview, readBaseline, ratchet,
}
