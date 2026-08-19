#!/usr/bin/env node
'use strict'
// SessionStart. Says one thing, once, and only when there is something to say.
// Anything printed here is paid for in every single session.
const path = require('path')
const fs = require('fs')
const { execFileSync } = require('child_process')
const { readInput, config, emit } = require(path.join(__dirname, 'lib.js'))

// The staleness check, remote sessions only: no network call and no output on
// a local one, where the checkout is the source and cannot be behind itself.
//
// It updates nothing. The CLI resolves a session's components before any hook
// runs, so an update from inside a session can only reach the next one -
// keeping the installation current is the job of the environment's setup
// script, which runs outside a session. What a session can do about its own
// staleness is exactly one thing: say so.
//
// The comparison needs no claude call and no hard-coded URL. The plugin pins
// no version, so the installed version is the source commit's SHA, and the CLI
// keys the checkout by it: CLAUDE_PLUGIN_ROOT is
// .../plugins/repos/<marketplace>/<sha>/plugins/forge, so the SHA and the
// marketplace both come out of that path. The tip is asked from the
// marketplace clone's own remote, which makes a fork check against the fork.
// No answer, no warning: with the network down there is nothing to compare
// against, and a wrong warning is worse than none.
function stale() {
  if (process.env.CLAUDE_CODE_REMOTE !== 'true') return null
  const root = process.env.CLAUDE_PLUGIN_ROOT
  if (!root) return null

  const parts = root.split(path.sep)
  const at = parts.map((p) => /^[0-9a-f]{7,40}$/.test(p)).lastIndexOf(true)
  if (at < 1) return null
  const running = parts[at]
  const name = parts[at - 1]

  const home = process.env.CLAUDE_CONFIG_DIR || path.join(require('os').homedir(), '.claude')
  const clone = path.join(home, 'plugins', 'marketplaces', name)

  let tip = ''
  try {
    tip = execFileSync('git', ['-C', clone, 'ls-remote', 'origin', 'HEAD'], {
      encoding: 'utf8',
      timeout: 10000,
      stdio: ['ignore', 'pipe', 'ignore'],
    }).split(/\s/)[0]
  } catch {
    return null
  }
  if (!tip || tip.startsWith(running)) return null

  return `WARNING: this session runs an outdated forge plugin (version ${running}, but the repository tip is ${tip}). Its agents, skills and workflows are the old ones, and a running session cannot swap them - tell the human, and recommend a fresh session after claude plugin update forge@${name}.`
}

// The rules the plugin owns travel with the plugin, injected here rather than
// copied into the project at bootstrap. A copy ages the moment the plugin is
// updated, and only a second bootstrap would notice. This costs the same as the
// file rule it replaces - both load once per session - and it is skipped for an
// unconfigured project, which cannot act on them anyway.
function rules() {
  try {
    return fs.readFileSync(path.join(__dirname, '..', 'rules', 'forge.md'), 'utf8').trim()
  } catch {
    return ''
  }
}

const input = readInput()
const say = []
if (config(input)) {
  const own = rules()
  if (own) say.push(own)
} else {
  say.push('forge is installed but this project is not set up. Run /forge:bootstrap.')
}
const outdated = stale()
if (outdated) say.push(outdated)
if (!say.length) emit(null)

emit({
  hookSpecificOutput: {
    hookEventName: 'SessionStart',
    additionalContext: say.join('\n'),
  },
})
