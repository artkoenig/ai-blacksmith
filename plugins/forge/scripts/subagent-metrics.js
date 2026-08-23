#!/usr/bin/env node
'use strict'
// SubagentStop. Appends one line per agent run so /forge:stats can show whether
// the token budget is actually holding, and /forge:context can put a measured
// number next to what the start hook estimated. Never blocks, never fails a run.
const fs = require('fs')
const path = require('path')
const { readInput, projectRoot, emit } = require('./lib.js')

const input = readInput()
const agentType = input.agent_type || ''
if (!agentType.startsWith('forge:') && !input.agent_id) emit(null)

const parse = (file) => {
  try {
    return fs
      .readFileSync(file, 'utf8')
      .split('\n')
      .filter(Boolean)
      .map((line) => {
        try {
          return JSON.parse(line)
        } catch {
          return null
        }
      })
      .filter(Boolean)
  } catch {
    return []
  }
}

// An agent writes its own transcript beside the session's. SubagentStop is handed
// both paths: `transcript_path` is the session's, `agent_transcript_path` the
// agent's own. Verified on Claude Code 2.1.237.
//
// Where a build does not send the second, derive it. The layout is
//   <project>/<session>/subagents/agent-<agentId>.jsonl                for a Task-spawned agent
//   <project>/<session>/subagents/workflows/<runId>/agent-<agentId>.jsonl  for one the Workflow tool spawned
// Every forge agent runs through a workflow, so the second layout is the one
// /forge:stats lives on.
function transcriptOf(input) {
  const given = input.transcript_path || ''
  const id = input.agent_id || ''
  if (!id) return given

  const own = input.agent_transcript_path || ''
  if (own && fs.existsSync(own)) return own

  const name = `agent-${id}.jsonl`
  const roots = [given.replace(/\.jsonl$/, ''), path.join(path.dirname(given), input.session_id || '')]
  for (const root of roots) {
    const dir = path.join(root, 'subagents')
    const direct = path.join(dir, name)
    if (fs.existsSync(direct)) return direct
    let runs = []
    try {
      runs = fs.readdirSync(path.join(dir, 'workflows'))
    } catch {
      runs = []
    }
    for (const run of runs) {
      const inRun = path.join(dir, 'workflows', run, name)
      if (fs.existsSync(inRun)) return inRun
    }
  }
  return given
}

// Narrow to this agent's turns. A transcript that does not name them is not this
// agent's, and measuring it would report the session's numbers as the agent's.
function ownTurns(entries, agentId) {
  const byId = entries.filter((e) => e.agentId && e.agentId === agentId)
  if (byId.length) return { turns: byId, matched: true }
  return { turns: [], matched: false }
}

const contextTokens = (usage) =>
  usage
    ? (usage.input_tokens || 0) + (usage.cache_creation_input_tokens || 0) + (usage.cache_read_input_tokens || 0)
    : null

function text(message) {
  const content = message && message.content
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  return content.map((block) => (typeof block === 'string' ? block : block && block.text) || '').join('')
}

let toolCalls = null
let startTokens = null
let peakTokens = null
let promptTokens = null
try {
  const file = transcriptOf(input)
  const { turns, matched } = ownTurns(parse(file), input.agent_id || '')

  toolCalls = turns.reduce(
    (n, e) =>
      n +
      (Array.isArray(e.message && e.message.content)
        ? e.message.content.filter((block) => block && block.type === 'tool_use').length
        : 0),
    0,
  )
  const replies = turns.filter((e) => e.type === 'assistant' && e.message && e.message.usage)
  startTokens = replies.length ? contextTokens(replies[0].message.usage) : null
  peakTokens = replies.reduce((n, e) => Math.max(n, contextTokens(e.message.usage) || 0), 0) || null

  const first = turns.find((e) => e.type === 'user' && e.message)
  promptTokens = first ? Math.round(text(first.message).length / 4) : null

  if (!matched) {
    // a hole is worth more than the session's numbers wearing the agent's name
    toolCalls = startTokens = peakTokens = promptTokens = null
  }
} catch {
  toolCalls = startTokens = peakTokens = promptTokens = null
}

try {
  const dir = path.join(projectRoot(input), '.forge')
  fs.mkdirSync(dir, { recursive: true })
  fs.appendFileSync(
    path.join(dir, 'metrics.jsonl'),
    JSON.stringify({
      at: new Date().toISOString(),
      session: input.session_id || '',
      agent: agentType,
      agentId: input.agent_id || '',
      toolCalls,
      startTokens,
      peakTokens,
      promptTokens,
    }) + '\n',
  )
} catch {
  // metrics are never worth failing a run over
}

emit(null)
