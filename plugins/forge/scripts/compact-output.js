#!/usr/bin/env node
'use strict'
// PostToolUse on Bash. Replaces an over-long stdout with head + tail and a path
// to the full log, so a verbose command costs a fixed number of tokens.
//
// stderr is never touched: stripping error detail makes the agent proceed on a
// false assumption, which costs far more than the tokens it saves.
const fs = require('fs')
const path = require('path')
const { readInput, projectRoot, config, emit } = require(require('path').join(__dirname, 'lib.js'))

const input = readInput()
const response = input.tool_response
if (!response || typeof response.stdout !== 'string') emit(null)

// Same gate as the guard: forge changes what an agent sees only in projects
// that opted in.
const cfg = config(input)
if (!cfg) emit(null)

const c = cfg.compaction || {}
const maxLines = Number(c.maxLines) > 0 ? Number(c.maxLines) : 60
const headLines = Number(c.headLines) > 0 ? Number(c.headLines) : 30
const tailLines = Number(c.tailLines) > 0 ? Number(c.tailLines) : 15

const lines = response.stdout.split('\n')
if (lines.length <= maxLines) emit(null)

const root = projectRoot(input)
const dir = path.join(root, '.forge', 'last')
let logPath = ''
try {
  fs.mkdirSync(dir, { recursive: true })
  const name = `bash-${input.tool_use_id || Date.now()}.log`
  fs.writeFileSync(path.join(dir, name), response.stdout)
  logPath = path.join('.forge', 'last', name)
} catch {
  logPath = ''
}

const omitted = lines.length - headLines - tailLines
const marker = logPath
  ? `… ${omitted} lines omitted → ${logPath}`
  : `… ${omitted} lines omitted`

emit({
  hookSpecificOutput: {
    hookEventName: 'PostToolUse',
    updatedToolOutput: {
      ...response,
      stdout: [...lines.slice(0, headLines), marker, ...lines.slice(-tailLines)].join('\n'),
    },
  },
})
