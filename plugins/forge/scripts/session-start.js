#!/usr/bin/env node
'use strict'
// SessionStart. Says one thing, once, and only when there is something to say.
// Anything printed here is paid for in every single session.
const path = require('path')
const fs = require('fs')
const { execFileSync } = require('child_process')
const { readInput, config, emit } = require('./lib.js')

// The staleness check.
//
// It updates nothing. The CLI resolves a session's components before any hook
// runs, so an update from inside a session can only reach the next one -
// keeping the installation current is the job of the environment's setup
// script, which runs outside a session. What a session can do about its own
// staleness is exactly one thing: say so.
//
// The comparison needs no claude call and no hard-coded URL. The plugin pins no
// version, so the installed version is the source commit's SHA, and the CLI
// keys the cache entry by it: CLAUDE_PLUGIN_ROOT is
// <cache>/<marketplace>/<plugin>/<version>, and the marketplace clone is the
// cache directory's sibling - both layouts are documented at
// https://code.claude.com/docs/en/plugin-marketplaces#pre-populate-plugins-for-containers
// and the version rule at
// https://code.claude.com/docs/en/plugins-reference#version-management.
// That path shape is also the gate: a development checkout or a link-mode
// source does not sit under the cache, and cannot be behind itself. The tip is
// asked from the marketplace clone's own remote, which makes a fork check
// against the fork. No answer, no warning: with the network down there is
// nothing to compare against, and a wrong warning is worse than none.
function stale() {
  const root = process.env.CLAUDE_PLUGIN_ROOT
  if (!root) return null

  const parts = root.split(path.sep).filter(Boolean)
  const at = parts.lastIndexOf('cache')
  if (at < 1 || parts.length - at !== 4) return null
  const [name, plugin, running] = parts.slice(at + 1)
  // A pinned version names no commit, so there is nothing a tip could be
  // compared against.
  if (!/^[0-9a-f]{7,40}$/.test(running)) return null

  const home = process.env.CLAUDE_CONFIG_DIR || path.join(require('os').homedir(), '.claude')
  const root0 = root.startsWith(path.sep) ? path.sep : ''
  const clone = [
    path.join(root0 + parts.slice(0, at).join(path.sep), 'marketplaces', name),
    path.join(home, 'plugins', 'marketplaces', name),
  ].find((d) => fs.existsSync(path.join(d, '.git')))
  if (!clone) return null

  const git = (args) =>
    execFileSync('git', ['-C', clone, ...args], {
      encoding: 'utf8',
      timeout: 5000,
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()

  let tip = ''
  try {
    // The clone sits on the ref the marketplace was added with, which is not
    // always the remote's default branch.
    let ref = ''
    try {
      ref = git(['rev-parse', '--abbrev-ref', 'HEAD'])
    } catch {}
    if (!ref || ref === 'HEAD') ref = 'HEAD'
    tip = git(['ls-remote', 'origin', ref]).split(/\s/)[0]
  } catch {
    return null
  }
  if (!tip || tip.startsWith(running)) return null

  return `WARNING: this session runs an outdated forge plugin (version ${running}, but the repository tip is ${tip}). Its agents, skills and workflows are the old ones, and a running session cannot swap them - tell the human, and recommend a fresh session after claude plugin update ${plugin}@${name}.`
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
