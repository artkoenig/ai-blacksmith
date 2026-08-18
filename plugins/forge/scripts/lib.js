'use strict'
const fs = require('fs')
const path = require('path')

function readInput() {
  let raw = ''
  try {
    raw = fs.readFileSync(0, 'utf8')
  } catch {
    return {}
  }
  try {
    return JSON.parse(raw)
  } catch {
    return {}
  }
}

function projectRoot(input) {
  return process.env.CLAUDE_PROJECT_DIR || (input && input.cwd) || process.cwd()
}

function config(input) {
  const file = path.join(projectRoot(input), '.forge', 'config.json')
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch {
    return null
  }
}

function emit(obj) {
  if (obj) process.stdout.write(JSON.stringify(obj))
  process.exit(0)
}

module.exports = { readInput, projectRoot, config, emit }
