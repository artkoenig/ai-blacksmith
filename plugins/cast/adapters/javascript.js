'use strict'
// The javascript/typescript adapter. Everything cast knows about the language
// is here: which files are modules, which text is an import, what kind of edge
// it makes, and how a specifier becomes another module.
//
// The scan engine (../scripts/cast.js) knows none of it. A second language is a
// second file in this directory, or in a project's own .cast/adapters/.
const path = require('path')
const { builtinModules } = require('module')

const SOURCE = ['.ts', '.tsx', '.mts', '.cts', '.js', '.jsx', '.mjs', '.cjs']
// A ".js" specifier in a typescript project names the ".ts" that compiles to it.
const REWRITE = { '.js': ['.ts', '.tsx'], '.mjs': ['.mts'], '.cjs': ['.cts'], '.jsx': ['.tsx'] }

// Order is the classification: the first pattern that claims a (line, specifier)
// wins, so `import type` is a type edge before it can be read as a value one.
// These are regexes, not a parser - see README.md for what that costs.
const patterns = [
  { kind: 'type', re: /(?:^|[\s;}])(?:import|export)\s+type\s[^;'"]*from\s*['"]([^'"]+)['"]/g },
  { kind: 'dynamic', re: /(?:^|[^\w.$])import\s*\(\s*['"]([^'"]+)['"]\s*\)/g },
  { kind: 'value', re: /(?:^|[\s;}])import\s[^;'"]*from\s*['"]([^'"]+)['"]/g },
  { kind: 'value', re: /(?:^|[\s;}])import\s*['"]([^'"]+)['"]/g },
  { kind: 'value', re: /(?:^|[\s;}])export\s[^;'"]*from\s*['"]([^'"]+)['"]/g },
  { kind: 'value', re: /(?:^|[^\w.$])require\s*\(\s*['"]([^'"]+)['"]\s*\)/g },
]

// tsconfig.json is the only configuration read, and only for baseUrl and paths:
// those are what make two spellings of one import the same edge.
function init(ctx) {
  const raw = ctx.read('tsconfig.json')
  const co = (raw && strip(raw).compilerOptions) || {}
  const baseUrl = typeof co.baseUrl === 'string' ? toPosix(co.baseUrl) : null
  return { baseUrl, paths: co.paths && typeof co.paths === 'object' ? co.paths : {} }
}

// tsconfig.json is JSON with comments and trailing commas often enough that a
// bare JSON.parse would silently lose every alias in the file.
function strip(raw) {
  try {
    const bare = raw
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:"'\\])\/\/[^\n]*/g, '$1')
      .replace(/,(\s*[}\]])/g, '$1')
    return JSON.parse(bare)
  } catch {
    return {}
  }
}

const toPosix = (p) => p.split(path.sep).join('/').replace(/^\.\//, '').replace(/\/$/, '')

// A specifier becomes one of three answers: a module of this project, something
// outside it, or nothing at all. Nothing at all is never dropped - the engine
// records it as unresolved so `cast report` can name it.
function resolve(spec, from, ctx) {
  const dir = path.posix.dirname(from)
  const cfg = ctx.state

  if (spec.startsWith('./') || spec.startsWith('../')) return file(path.posix.join(dir, spec), ctx)

  // An alias that matched is answered by the alias: falling through to a package
  // lookup would report a broken alias as an external dependency.
  const candidates = alias(spec, cfg)
  if (candidates.length) {
    for (const c of candidates) {
      const hit = file(cfg.baseUrl ? path.posix.join(cfg.baseUrl, c) : c, ctx)
      if (hit) return hit
    }
    return null
  }

  if (cfg.baseUrl !== null) {
    const hit = file(path.posix.join(cfg.baseUrl, spec), ctx)
    if (hit) return hit
  }

  const pkg = spec.startsWith('@') ? spec.split('/').slice(0, 2).join('/') : spec.split('/')[0]
  if (spec.startsWith('node:') || builtinModules.includes(pkg)) return { external: true }
  if (ctx.exists(path.posix.join('node_modules', pkg))) return { external: true }
  return null
}

function alias(spec, cfg) {
  const out = []
  for (const [pattern, targets] of Object.entries(cfg.paths || {})) {
    const star = pattern.indexOf('*')
    if (star === -1) {
      if (pattern === spec) out.push(...[].concat(targets))
      continue
    }
    const head = pattern.slice(0, star)
    const tail = pattern.slice(star + 1)
    if (!spec.startsWith(head) || !spec.endsWith(tail)) continue
    if (spec.length < head.length + tail.length) continue
    const rest = spec.slice(head.length, spec.length - tail.length)
    for (const t of [].concat(targets)) out.push(toPosix(t).replace('*', rest))
  }
  return out
}

// One path, every spelling the language allows for it: the file itself, the file
// with a source extension, and the directory's index.
function file(p, ctx) {
  const clean = path.posix.normalize(p)
  if (ctx.isFile(clean)) return { to: clean }
  const ext = path.posix.extname(clean)
  for (const cand of REWRITE[ext] || []) {
    const swapped = clean.slice(0, -ext.length) + cand
    if (ctx.isFile(swapped)) return { to: swapped }
  }
  for (const e of SOURCE) if (ctx.isFile(clean + e)) return { to: clean + e }
  for (const e of SOURCE) if (ctx.isFile(clean + '/index' + e)) return { to: clean + '/index' + e }
  return null
}

module.exports = {
  name: 'javascript',
  extensions: SOURCE,
  ignore: ['node_modules', 'dist', 'build', 'coverage', 'out'],
  patterns,
  init,
  resolve,
}
