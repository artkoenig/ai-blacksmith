export const meta = {
  name: 'work',
  description: 'Implement one prepared issue autonomously, loop until the review converges, then commit',
  whenToUse:
    'Run /forge:work <issue-id> to execute an issue written by /forge:issue. No user interaction is possible during the run.',
  phases: [
    { title: 'Implement', detail: 'read the issue, branch, write the code' },
    { title: 'Review', detail: 'check the acceptance criteria against the branch diff' },
    { title: 'Commit', detail: 'commit on the branch' },
  ],
}

// The loop runs until the verdict converges. Convergence is one of two things:
//
//   pass      every criterion holds - the fixed point we want
//   stalled   a round produced exactly the same failed set as the round before
//             it, so the implementer is no longer moving and further rounds
//             would burn tokens on the same wall
//
// MAX_ROUNDS is only a runaway backstop for a loop that oscillates between two
// different failed sets forever. Stall detection normally ends the loop first.
const MAX_ROUNDS = 8

const RESULT = {
  type: 'object',
  required: ['status', 'branch', 'base', 'summary', 'acceptance'],
  properties: {
    status: { type: 'string', enum: ['implemented', 'blocked'] },
    branch: { type: 'string', description: 'branch the work sits on, empty when blocked' },
    base: {
      type: 'string',
      description: 'commit sha the branch was cut from, so the review can diff against it',
    },
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
const maxRounds = args && Number(args.maxRounds) > 0 ? Number(args.maxRounds) : MAX_ROUNDS

if (!issue) {
  return { status: 'error', reason: 'No issue id. Run /forge:work <issue-id>.' }
}

const RULES = [
  'You cannot ask the user anything. Decide and proceed.',
  'Use forge-test, forge-lint, forge-typecheck, forge-build. Never call the raw runners.',
  'Escalate detail only after a failure: bare command, then --failing, then --detail <id>.',
  'Return the requested object. No prose, no summary of your steps.',
].join('\n')

const STAGE = [
  'When you are done, stage everything with `git add -A`. Do not commit.',
  'Staging is what makes your work visible to the review, new files included.',
].join('\n')

phase('Implement')

let run = await agent(
  [
    `Implement issue ${issue}.`,
    '',
    'Steps:',
    `1. Read issue ${issue} through the project's issue-backend skill.`,
    '2. Check your memory before any search tool. The issue carries a Context block with the files to touch; trust it and do not explore beyond it.',
    `3. Note the current commit sha - that is the base. Then create and switch to branch forge/${issue}.`,
    '4. Implement the change. Touch only the files the issue lists.',
    '5. Run forge-test once when done.',
    '6. Record durable project knowledge in your memory. Nothing issue-specific.',
    '',
    STAGE,
    '',
    'Return status "blocked" with a blocker instead of guessing when the issue is unworkable.',
    'Copy the acceptance criteria into the acceptance field verbatim, including the verify command of each.',
    'Return the base sha you noted in step 3.',
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
let previousFailed = null
let round = 0

while (true) {
  phase('Review')

  // A fresh reviewer every round, with no memory, judging the whole accumulated
  // diff rather than the last round's increment. Judging only the increment
  // would report criteria that an earlier round already satisfied as unmet, and
  // would miss a repair that broke one of them.
  verdict = await agent(
    [
      `Review the work for issue ${issue} on branch ${run.branch}.`,
      '',
      `The diff to judge is \`git diff ${run.base}\`. That is everything the implementer has produced`,
      'on this branch so far, staged changes and new files included. Use exactly this command; do not',
      'guess a base branch name.',
      '',
      'Acceptance criteria:',
      ...run.acceptance.map((c) => `${c.id}: ${c.text}${c.verify ? ` | verify: ${c.verify}` : ''}`),
      '',
      'Check every criterion, not only the ones that failed before - a repair can break a criterion',
      'that used to hold. Run each verify command where one is given.',
      'Judge only these criteria. Style opinions are out of scope.',
      'Set pass true only when every criterion holds.',
      '',
      RULES,
    ].join('\n'),
    { agentType: 'forge:reviewer', schema: VERDICT, effort: 'low', label: `review:round-${round}`, phase: 'Review' },
  )

  if (!verdict) return { status: 'error', issue, branch: run.branch, reason: 'Reviewer did not return a verdict.' }
  if (verdict.pass) break

  const failed = [...(verdict.failed || [])].sort().join(',')

  if (failed === previousFailed) {
    log(`${issue}: converged on a failure after ${round} rounds - same criteria failing twice`)
    return {
      status: 'stalled',
      issue,
      branch: run.branch,
      rounds: round,
      failed: verdict.failed,
      notes: verdict.notes || [],
      hint: 'The implementer stopped making progress. Staged work is on the branch. Fix it by hand or sharpen the acceptance criteria.',
    }
  }

  if (round >= maxRounds) {
    log(`${issue}: hit the ${maxRounds}-round cap without converging`)
    return {
      status: 'failed',
      issue,
      branch: run.branch,
      rounds: round,
      failed: verdict.failed,
      notes: verdict.notes || [],
      hint: 'The verdict kept changing without converging. Staged work is on the branch.',
    }
  }

  previousFailed = failed
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
      `Return the same base sha as before: ${run.base}.`,
      '',
      STAGE,
      '',
      RULES,
    ].join('\n'),
    { agentType: 'forge:implementer', schema: RESULT, label: `repair:round-${round}`, phase: 'Implement' },
  )

  if (!repair) return { status: 'error', issue, branch: run.branch, reason: `Repair round ${round} returned nothing.` }
  if (repair.status === 'blocked') {
    return { status: 'blocked', issue, branch: run.branch, rounds: round, blocker: repair.blocker || 'unspecified' }
  }

  run = {
    ...repair,
    base: run.base,
    branch: run.branch,
    acceptance: repair.acceptance && repair.acceptance.length ? repair.acceptance : run.acceptance,
  }
}

phase('Commit')

const commit = await agent(
  [
    `Commit the work for issue ${issue} on branch ${run.branch}.`,
    '',
    'Everything is already staged. Do not push. Do not open a pull request.',
    `Message: first line "${issue}: ${run.summary}", then a blank line, then one bullet per acceptance criterion.`,
    '',
    RULES,
  ].join('\n'),
  { agentType: 'forge:implementer', schema: COMMIT, label: `commit:${issue}`, phase: 'Commit' },
)

if (!commit || !commit.committed) {
  return { status: 'uncommitted', issue, branch: run.branch, summary: run.summary, rounds: round }
}

return {
  status: 'done',
  issue,
  branch: run.branch,
  sha: commit.sha || '',
  summary: run.summary,
  rounds: round,
}
