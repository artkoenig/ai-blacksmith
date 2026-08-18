#!/usr/bin/env node
'use strict'
// SubagentStart. Records what an agent carries into its first turn: the agent
// definition, the skills it declares, the project rules - each with a size, and
// a copy saved beside the record so the content can be read back after the run.
// Never blocks, never fails a run.
const fs = require('fs')
const path = require('path')
const os = require('os')
const { readInput, projectRoot, emit } = require(require('path').join(__dirname, 'lib.js'))

const DUMP_MAX_BYTES = 256 * 1024 // one source larger than this is measured, not copied
const KEEP_RUNS = 20 // dumps of older runs are pruned

const estTokens = (text) => Math.round(text.length / 4)

// Front matter, only as far as this script needs it: scalars and `- ` lists.
function frontMatter(text) {
  const out = {}
  if (!text.startsWith('---')) return out
  const end = text.indexOf('\n---', 3)
  if (end < 0) return out
  let key = null
  for (const line of text.slice(text.indexOf('\n') + 1, end).split('\n')) {
    const item = line.match(/^\s+-\s+(.*)$/)
    if (item && key) {
      ;(out[key] = Array.isArray(out[key]) ? out[key] : []).push(item[1].trim())
      continue
    }
    const pair = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/)
    if (!pair) continue
    key = pair[1]
    out[key] = pair[2].trim() === '' ? [] : pair[2].trim()
  }
  return out
}

const firstFile = (candidates) => candidates.find((p) => p && fs.existsSync(p) && fs.statSync(p).isFile())

function main(input) {
  const root = projectRoot(input)
  const agent = String(input.agent_type || '').replace(/^[\w-]+:/, '')
  if (!agent) return
  const pluginRoot = process.env.CLAUDE_PLUGIN_ROOT || path.join(__dirname, '..')
  const home = os.homedir()

  const sources = []
  const files = [] // the resolved path of each source, in the order they were added
  const seen = new Set()
  const add = (kind, file, opts = {}) => {
    if (!file) return null
    let real
    try {
      real = fs.realpathSync(file)
    } catch {
      return null
    }
    if (seen.has(real)) return null // an agent may name the same skill twice, prefixed and bare
    seen.add(real)
    let text
    try {
      text = fs.readFileSync(real, 'utf8')
    } catch {
      return null
    }
    const lines = text.split('\n')
    const loadedText = opts.maxLines ? lines.slice(0, opts.maxLines).join('\n') : text
    const entry = {
      kind,
      path: path.relative(root, real) || real,
      bytes: Buffer.byteLength(loadedText),
      lines: loadedText.split('\n').length,
      estTokens: estTokens(loadedText),
      loaded: opts.loaded !== false,
    }
    if (loadedText.length !== text.length) entry.bytesFull = Buffer.byteLength(text)
    sources.push(entry)
    files.push(real)
    return { entry, real, text }
  }

  // The agent definition, and the skills it declares.
  const agentFile = firstFile([
    path.join(root, '.claude', 'agents', agent + '.md'),
    path.join(pluginRoot, 'agents', agent + '.md'),
    path.join(home, '.claude', 'agents', agent + '.md'),
  ])
  const added = add('agent', agentFile)
  const meta = added ? frontMatter(added.text) : {}

  for (const declared of [].concat(meta.skills || [])) {
    const name = String(declared).replace(/^[\w-]+:/, '')
    add(
      'skill',
      firstFile([
        path.join(root, '.claude', 'skills', name, 'SKILL.md'),
        path.join(pluginRoot, 'skills', name, 'SKILL.md'),
        path.join(home, '.claude', 'skills', name, 'SKILL.md'),
      ]),
    )
  }

  // Project instructions reach every agent whether it asks for them or not.
  add('rules', firstFile([path.join(root, 'CLAUDE.md')]))
  add('rules', firstFile([path.join(root, '.claude', 'CLAUDE.md')]))
  let ruleFiles = []
  try {
    ruleFiles = fs.readdirSync(path.join(root, '.claude', 'rules')).filter((f) => f.endsWith('.md'))
  } catch {
    ruleFiles = []
  }
  for (const file of ruleFiles.sort()) add('rules', path.join(root, '.claude', 'rules', file))

  const agentId = String(input.agent_id || '') || `${input.session_id || 'session'}-${Date.now()}`
  const record = {
    at: new Date().toISOString(),
    session: input.session_id || '',
    agentId,
    agent: input.agent_type || '',
    estTokens: sources.filter((s) => s.loaded).reduce((n, s) => n + s.estTokens, 0),
    sources,
  }

  // The copies. A record says how large the context was; the copies say what was in it.
  const dumpDir = path.join(root, '.forge', 'context', agentId.replace(/[^\w.-]/g, '_'))
  fs.mkdirSync(dumpDir, { recursive: true })
  sources.forEach((source, i) => {
    if (!source.loaded || source.bytes > DUMP_MAX_BYTES) return
    const name = `${String(i + 1).padStart(2, '0')}-${source.kind}-${path.basename(source.path)}`
    try {
      fs.copyFileSync(files[i], path.join(dumpDir, name))
      source.dump = name
    } catch {
      // a source that cannot be copied is still measured
    }
  })
  record.dump = path.relative(root, dumpDir)
  fs.writeFileSync(path.join(dumpDir, 'index.json'), JSON.stringify(record, null, 2) + '\n')
  fs.appendFileSync(path.join(root, '.forge', 'context.jsonl'), JSON.stringify(record) + '\n')

  prune(path.join(root, '.forge', 'context'))
}

function prune(dir) {
  let runs
  try {
    runs = fs.readdirSync(dir).map((name) => ({ name, at: fs.statSync(path.join(dir, name)).mtimeMs }))
  } catch {
    return
  }
  runs.sort((a, b) => b.at - a.at)
  for (const run of runs.slice(KEEP_RUNS)) {
    try {
      fs.rmSync(path.join(dir, run.name), { recursive: true, force: true })
    } catch {
      // a dump that will not go away is not worth a failed run
    }
  }
}

const input = readInput()
try {
  main(input)
} catch {
  // measurement is never worth failing a run over
}

emit(null)
