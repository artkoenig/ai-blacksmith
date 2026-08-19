#!/usr/bin/env node
'use strict'
// PostToolUse on Bash. A command that returns more than a budget of lines or
// characters gets its stdout withheld: the full text goes to a log, and the
// agent is told the size, the path, and the cheaper ways to read it. Under the
// budget nothing is touched.
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
const maxLines = Number(c.maxLines) > 0 ? Number(c.maxLines) : 200
const maxChars = Number(c.maxChars) > 0 ? Number(c.maxChars) : 10000

const lines = response.stdout.split('\n')
if (lines.length <= maxLines && response.stdout.length <= maxChars) emit(null)

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

// Withholding without a log would destroy the output. An expensive result the
// agent can still read beats a cheap one nobody can recover.
if (!logPath) emit(null)

emit({
  hookSpecificOutput: {
    hookEventName: 'PostToolUse',
    updatedToolOutput: {
      ...response,
      stdout: [
        `… output withheld: ${lines.length} lines, ${response.stdout.length} characters → ${logPath}`,
        'This command asked for more than a context window is worth. Do not re-run it to see',
        'the rest. Query the log instead, or narrow the command and run it again:',
        `  grep -n '<pattern>' ${logPath}`,
        `  sed -n '1,40p' ${logPath}   # or tail -n 40, or the Read tool with offset/limit`,
        '  the Grep tool on that path with output_mode "content"',
      ].join('\n'),
    },
  },
})
