#!/usr/bin/env node
'use strict'
// PreToolUse on Bash. Rewrites a raw runner into its forge wrapper when the
// mapping is exact, and refuses it with a one-line reason when it is not.
//
// The rewrite is deliberately conservative: only a bare invocation is rewritten.
// A command carrying its own flags could mean something the wrapper does not,
// so it is refused with the wrapper named rather than silently reinterpreted.
const { readInput, config, emit } = require('./lib.js')

const DEFAULT_RULES = [
  { match: '(npm|pnpm|yarn|bun) (run )?test', wrapper: 'forge-test' },
  { match: '(npx |bunx )?(jest|vitest)', wrapper: 'forge-test' },
  { match: '(python3? -m )?pytest', wrapper: 'forge-test' },
  { match: 'go test( \\./\\.\\.\\.)?', wrapper: 'forge-test' },
  { match: 'cargo test', wrapper: 'forge-test' },
  { match: '(npx |bunx )?tsc( --noEmit)?', wrapper: 'forge-typecheck' },
  { match: '(npm|pnpm|yarn|bun) (run )?typecheck', wrapper: 'forge-typecheck' },
  { match: '(npx |bunx )?eslint( \\.)?', wrapper: 'forge-lint' },
  { match: '(npm|pnpm|yarn|bun) (run )?lint', wrapper: 'forge-lint' },
  { match: '(npm|pnpm|yarn|bun) (run )?build', wrapper: 'forge-build' },
  { match: 'cargo build', wrapper: 'forge-build' },
]

const input = readInput()
const command = ((input.tool_input && input.tool_input.command) || '').trim()
if (!command) emit(null)

// Only act where forge is set up. With the plugin enabled globally and no
// project config, the wrappers have nothing to run, so refusing the raw command
// would break a project that never asked for forge.
const cfg = config(input)
if (!cfg) emit(null)

const rules = (cfg && cfg.guard && Array.isArray(cfg.guard.rewrite) ? cfg.guard.rewrite : []).concat(DEFAULT_RULES)

for (const rule of rules) {
  let bare, prefix
  try {
    bare = new RegExp(`^${rule.match}$`)
    prefix = new RegExp(`^${rule.match}\\b`)
  } catch {
    continue
  }

  if (bare.test(command)) {
    emit({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'allow',
        permissionDecisionReason: `forge: rewritten to ${rule.wrapper}`,
        updatedInput: { ...input.tool_input, command: rule.wrapper },
      },
    })
  }

  if (prefix.test(command)) {
    emit({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason:
          `Use ${rule.wrapper} instead. It exits 0 with one line, or 1 with every ` +
          `failure and its detail. Add --run <pattern> for a subset.`,
      },
    })
  }
}

emit(null)
