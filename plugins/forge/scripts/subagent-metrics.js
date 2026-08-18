#!/usr/bin/env node
'use strict'
// SubagentStop. Appends one line per agent run so /forge:stats can show whether
// the token budget is actually holding. Never blocks, never fails a run.
const fs = require('fs')
const path = require('path')
const { readInput, projectRoot, emit } = require(require('path').join(__dirname, 'lib.js'))

const input = readInput()
const agentType = input.agent_type || ''
if (!agentType.startsWith('forge:') && !input.agent_id) emit(null)

let toolCalls = null
try {
  const raw = fs.readFileSync(input.transcript_path, 'utf8')
  toolCalls = (raw.match(/"type"\s*:\s*"tool_use"/g) || []).length
} catch {
  toolCalls = null
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
    }) + '\n',
  )
} catch {
  // metrics are never worth failing a run over
}

emit(null)
