#!/usr/bin/env node
'use strict'
// SessionStart. Says one thing, once, and only when the project is not set up.
// Anything printed here is paid for in every single session.
const { readInput, config, emit } = require(require('path').join(__dirname, 'lib.js'))

const input = readInput()
if (config(input)) emit(null)

emit({
  hookSpecificOutput: {
    hookEventName: 'SessionStart',
    additionalContext: 'forge is installed but this project is not set up. Run /forge:bootstrap.',
  },
})
