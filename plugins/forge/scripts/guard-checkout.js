#!/usr/bin/env node
'use strict'
// PreToolUse on the file-writing tools: the reviewer writes nothing into the
// checkout it is judging.
//
// This is the mechanical shadow of a rule the reviewer's own page already
// carries. A page can say "you touch no code" and be obeyed every time but the
// one that matters, and a reviewer that edits the tree under review is reviewing
// its own work - what lands is no longer what the run judged.
//
// The reviewer still needs Write and Edit to be useful: it settles a doubt with
// a probe. That probe belongs in a worktree it builds outside the checkout, so
// the boundary is the checkout itself, not a directory inside it. Anything
// outside passes.
const path = require('path')
const { readInput, projectRoot, emit } = require(require('path').join(__dirname, 'lib.js'))

const input = readInput()
if (input.agent_type !== 'forge:reviewer') emit(null)

const target = (input.tool_input && (input.tool_input.file_path || input.tool_input.notebook_path)) || ''
if (!target) emit(null)

const root = path.resolve(projectRoot(input))
const resolved = path.resolve(input.cwd || root, target)

const inCheckout = resolved === root || resolved.startsWith(root + path.sep)
if (!inCheckout) emit(null)

emit({
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'deny',
    permissionDecisionReason:
      'Reviewers write nothing into the checkout under review. To run something against another ' +
      'state, or to settle a doubt with a probe, build a worktree outside the checkout with ' +
      '`git worktree add <tmp-dir> <ref>`, work there, and remove it. Report what a criterion ' +
      'needs; do not implement it.',
  },
})
