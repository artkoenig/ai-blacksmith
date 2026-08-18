export const meta = {
  name: 'work',
  description: 'Implement one prepared issue autonomously and commit it on a branch',
  whenToUse:
    'Run /forge:work <issue-id> to execute an issue written by /forge:issue. No user interaction is possible during the run.',
  phases: [
    { title: 'Implement', detail: 'read the issue, branch, write the code' },
    { title: 'Review', detail: 'check the acceptance criteria against the diff' },
    { title: 'Commit', detail: 'commit on the branch' },
  ],
}

const MAX_REPAIR_ROUNDS = 2

const RESULT = {
  type: 'object',
  required: ['status', 'branch', 'summary', 'acceptance'],
  properties: {
    status: { type: 'string', enum: ['implemented', 'blocked'] },
    branch: { type: 'string', description: 'branch the work sits on, empty when blocked' },
    summary: { type: 'string', description: 'one line, what changed' },
    files: { type: 'array', items: { type: 'string' } },
    acceptance: {
      type: 'array',
      description: 'the acceptance criteria copied verbatim from the issue',
      items: {
        type: 'object',
        required: ['id', 'text'],
        properties: {
          id: { type: 'string' },
          text: { type: 'string' },
          verify: { type: 'string', description: 'command that checks it, empty if none' },
        },
      },
    },
    blocker: { type: 'string', description: 'why it could not be done, empty otherwise' },
  },
}

const VERDICT = {
  type: 'object',
  required: ['pass', 'failed'],
  properties: {
    pass: { type: 'boolean' },
    failed: { type: 'array', items: { type: 'string' }, description: 'ids of failed criteria' },
    notes: { type: 'array', items: { type: 'string' }, description: 'one line per failed criterion' },
  },
}

const COMMIT = {
  type: 'object',
  required: ['committed'],
  properties: {
    committed: { type: 'boolean' },
    sha: { type: 'string' },
    message: { type: 'string' },
  },
}

const issue = typeof args === 'string' ? args.trim() : args && args.issue ? String(args.issue) : ''

if (!issue) {
  return { status: 'error', reason: 'No issue id. Run /forge:work <issue-id>.' }
}

const RULES = [
  'You cannot ask the user anything. Decide and proceed.',
  'Use forge-test, forge-lint, forge-typecheck, forge-build. Never call the raw runners.',
  'Escalate detail only after a failure: bare command, then --failing, then --detail <id>.',
  'Return the requested object. No prose, no summary of your steps.',
].join('\n')

phase('Implement')

let run = await agent(
  [
    `Implement issue ${issue}.`,
    '',
    'Steps:',
    `1. Read issue ${issue} through the project's issue-backend skill.`,
    '2. Check your memory before any search tool. The issue carries a Context block with the files to touch; trust it and do not explore beyond it.',
    `3. Create and switch to branch forge/${issue}.`,
    '4. Implement the change. Touch only the files the issue lists.',
    '5. Run forge-test once when done.',
    '6. Record durable project knowledge in your memory. Nothing issue-specific.',
    '',
    'Return status "blocked" with a blocker instead of guessing when the issue is unworkable.',
    'Copy the acceptance criteria into the acceptance field verbatim, including the verify command of each.',
    '',
    RULES,
  ].join('\n'),
  { agentType: 'forge:implementer', schema: RESULT, label: `implement:${issue}`, phase: 'Implement' },
)

if (!run) {
  return {
    status: 'error',
    issue,
    reason:
      'Implementer returned nothing. Check that the plugin-scoped agent type forge:implementer ' +
      'resolves; if it does not, the run never started.',
  }
}
if (run.status === 'blocked') return { status: 'blocked', issue, blocker: run.blocker || 'unspecified' }

let verdict = null
let round = 0

while (true) {
  phase('Review')
  verdict = await agent(
    [
      `Review the work on branch ${run.branch} for issue ${issue}.`,
      '',
      'Acceptance criteria:',
      ...run.acceptance.map((c) => `${c.id}: ${c.text}${c.verify ? ` | verify: ${c.verify}` : ''}`),
      '',
      'Check each criterion against the diff (git diff main...HEAD) and by running its verify command where one is given.',
      'Judge only these criteria. Style opinions are out of scope.',
      'Set pass true only when every criterion holds.',
      '',
      RULES,
    ].join('\n'),
    { agentType: 'forge:reviewer', schema: VERDICT, effort: 'low', label: `review:round-${round}`, phase: 'Review' },
  )

  if (!verdict) return { status: 'error', issue, branch: run.branch, reason: 'Reviewer did not return a verdict.' }
  if (verdict.pass) break

  if (round >= MAX_REPAIR_ROUNDS) {
    log(`${issue}: still failing after ${MAX_REPAIR_ROUNDS} repair rounds, stopping`)
    return {
      status: 'failed',
      issue,
      branch: run.branch,
      failed: verdict.failed,
      notes: verdict.notes || [],
      hint: 'Uncommitted work is on the branch. Fix by hand or sharpen the acceptance criteria.',
    }
  }

  round++
  phase('Implement')
  const repair = await agent(
    [
      `Repair round ${round} for issue ${issue} on branch ${run.branch}.`,
      '',
      `Fix only these criteria: ${verdict.failed.join(', ')}.`,
      ...(verdict.notes || []).map((n) => `- ${n}`),
      '',
      'Change nothing else. Re-run only the checks that cover these criteria.',
      'Copy the acceptance criteria into the acceptance field verbatim again.',
      '',
      RULES,
    ].join('\n'),
    { agentType: 'forge:implementer', schema: RESULT, label: `repair:round-${round}`, phase: 'Implement' },
  )

  if (!repair) return { status: 'error', issue, branch: run.branch, reason: `Repair round ${round} returned nothing.` }
  if (repair.status === 'blocked') {
    return { status: 'blocked', issue, branch: run.branch, blocker: repair.blocker || 'unspecified' }
  }
  run = { ...repair, acceptance: repair.acceptance.length ? repair.acceptance : run.acceptance }
}

phase('Commit')

const commit = await agent(
  [
    `Commit the work for issue ${issue} on branch ${run.branch}.`,
    '',
    'Stage only files that belong to this issue. Do not push. Do not open a pull request.',
    `Message: first line "${issue}: ${run.summary}", then a blank line, then one bullet per acceptance criterion that was met.`,
    '',
    RULES,
  ].join('\n'),
  { agentType: 'forge:implementer', schema: COMMIT, label: `commit:${issue}`, phase: 'Commit' },
)

if (!commit || !commit.committed) {
  return { status: 'uncommitted', issue, branch: run.branch, summary: run.summary, repairRounds: round }
}

return {
  status: 'done',
  issue,
  branch: run.branch,
  sha: commit.sha || '',
  summary: run.summary,
  repairRounds: round,
}
