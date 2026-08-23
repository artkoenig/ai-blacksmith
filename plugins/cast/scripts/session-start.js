#!/usr/bin/env node
'use strict'
// SessionStart. Says one thing, once, and only when there is something to say.
// Anything printed here is paid for in every single session.
//
// The rule the plugin owns travels with the plugin, injected here rather than
// copied into the project at install time. A copy ages the moment the plugin is
// updated, and nothing would notice. One file read is the whole cost.
//
// A project that carries the rule itself is not charged for it twice: the cast
// checkout links .claude/rules/cast.md to this plugin's copy, and the harness
// already loads it there as a project rule.
const fs = require('fs')
const path = require('path')

function readInput() {
  try {
    return JSON.parse(fs.readFileSync(0, 'utf8'))
  } catch {
    return {}
  }
}

function rule() {
  try {
    return fs.readFileSync(path.join(__dirname, '..', 'rules', 'cast.md'), 'utf8').trim()
  } catch {
    return ''
  }
}

const input = readInput()
const root = process.env.CLAUDE_PROJECT_DIR || (input && input.cwd) || process.cwd()
if (fs.existsSync(path.join(root, '.claude', 'rules', 'cast.md'))) process.exit(0)

const own = rule()
if (!own) process.exit(0)

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: own,
    },
  })
)
process.exit(0)
