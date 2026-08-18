#!/usr/bin/env node
'use strict'
// SubagentStop. Appends one line per agent run so /forge:stats can show whether
// the token budget is actually holding, and /forge:context can put a measured
// number next to what the start hook estimated. Never blocks, never fails a run.
const fs = require('fs')
const path = require('path')
const { readInput, projectRoot, emit } = require(require('path').join(__dirname, 'lib.js'))

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

// The transcript may be the agent's own, or the session's with the agent's turns
// folded in as a sidechain. Narrow to this agent's turns, from the widest signal
// down to the narrowest.
function ownTurns(entries, agentId) {
  const byId = entries.filter((e) => e.agentId && e.agentId === agentId)
  if (byId.length) return { turns: byId, matched: true }
  const side = entries.filter((e) => e.isSidechain)
  if (!side.length) return { turns: entries, matched: false }
  let start = 0
  side.forEach((e, i) => {
    if (e.type === 'user' && !e.parentUuid) start = i
  })
  return { turns: side.slice(start), matched: true }
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
  const dir = path.dirname(input.transcript_path || '')
  const id = input.agent_id || ''
  const file =
    [path.join(dir, id + '.jsonl'), path.join(dir, input.session_id || '', id + '.jsonl')].find(
      (p) => id && fs.existsSync(p),
    ) || input.transcript_path
  const { turns, matched } = ownTurns(parse(file), id)

  toolCalls = turns.reduce(
    (n, e) =>
      n +
      (Array.isArray(e.message && e.message.content)
        ? e.message.content.filter((block) => block && block.type === 'tool_use').length
        : 0),
    0,
  )
  if (!toolCalls && !matched) {
    // a transcript that does not mark its turns at all: count what is there
    const raw = fs.readFileSync(file, 'utf8')
    toolCalls = (raw.match(/"type"\s*:\s*"tool_use"/g) || []).length
  }

  const replies = turns.filter((e) => e.type === 'assistant' && e.message && e.message.usage)
  startTokens = replies.length ? contextTokens(replies[0].message.usage) : null
  peakTokens = replies.reduce((n, e) => Math.max(n, contextTokens(e.message.usage) || 0), 0) || null

  const first = turns.find((e) => e.type === 'user' && e.message)
  promptTokens = first ? Math.round(text(first.message).length / 4) : null
} catch {
  toolCalls = toolCalls || null
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
