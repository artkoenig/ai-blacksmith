export const meta = {
  name: 'work',
  description: 'Implement one issue autonomously - one loop per increment, in parallel where the cut allows',
  whenToUse:
    'Run /forge:work <issue-id> to execute an issue written by /forge:issue, or pass a cut to run its increments. No user interaction is possible during the run.',
  phases: [
    { title: 'Prepare', detail: 'cut the issue branch' },
    { title: 'Implement', detail: 'a worktree per increment where the issue was cut' },
    { title: 'Review', detail: 'judge each increment against its criteria' },
    { title: 'Commit', detail: 'commit the increment' },
    { title: 'Merge', detail: 'accepted increments onto the issue branch, in order' },
  ],
}

// Each increment's loop runs until its verdict converges. Convergence is one of
// two things:
//
//   pass      every criterion holds - the fixed point we want
//   stalled   a round produced exactly the same failed set as the round before
//             it, so the implementer is no longer moving and further rounds
//             would burn tokens on the same wall
//
// MAX_ROUNDS is only a runaway backstop for a loop that oscillates between two
// different failed sets forever. Stall detection normally ends the loop first.
const MAX_ROUNDS = 8

// The reviewer reads the issue itself and judges the diff. It is handed nothing
// the implementer wrote about its own work - no summary of what was built, no
// restatement of the criteria - because a reviewer reading the implementer's
// account of the change is grading the account, not the change.
const RESULT = {
  type: 'object',
  required: ['status', 'branch', 'worktree', 'summary'],
  properties: {
    status: { type: 'string', enum: ['implemented', 'blocked'] },
    branch: { type: 'string', description: 'increment branch, empty when blocked' },
    worktree: { type: 'string', description: 'absolute path of this increment worktree, empty when blocked' },
    base: { type: 'string', description: 'commit the increment branch was cut from' },
    summary: { type: 'string', description: 'one line, what changed - for the commit message' },
    files: { type: 'array', items: { type: 'string' } },
    blocker: { type: 'string', description: 'why it could not be done, empty otherwise' },
  },
}

const VERDICT = {
  type: 'object',
  required: ['pass', 'failed'],
  properties: {
    pass: { type: 'boolean' },
    failed: { type: 'array', items: { type: 'string' }, description: 'ids of failed criteria' },
    notes: {
      type: 'array',
      items: { type: 'string' },
      description: 'one line per failed criterion: what is wrong and how you reproduced it',
    },
    preexisting: {
      type: 'array',
      items: { type: 'string' },
      description: 'failures this change did not cause, proven at the base. Reported, never a finding',
    },
  },
}

const COMMIT = {
  type: 'object',
  required: ['committed'],
  properties: {
    committed: { type: 'boolean' },
    sha: { type: 'string' },
  },
}

const PREPARE = {
  type: 'object',
  required: ['branch', 'base'],
  properties: {
    branch: { type: 'string', description: 'the issue branch' },
    base: { type: 'string', description: 'commit sha the issue branch was cut from' },
  },
}

const MERGE = {
  type: 'object',
  required: ['results'],
  properties: {
    results: {
      type: 'array',
      items: {
        type: 'object',
        required: ['increment', 'merged'],
        properties: {
          increment: { type: 'string' },
          merged: { type: 'boolean' },
          sha: { type: 'string' },
          conflict: { type: 'string', description: 'what conflicted, empty when it merged' },
        },
      },
    },
  },
}

// ---------------------------------------------------------------------------
// Input. A bare issue id is one increment covering every criterion in the
// issue, which is what an uncut issue means.
// ---------------------------------------------------------------------------
const input = typeof args === 'string' ? { issue: args.trim() } : args || {}
const issue = input.issue ? String(input.issue).trim() : ''
const maxRounds = Number(input.maxRounds) > 0 ? Number(input.maxRounds) : MAX_ROUNDS

if (!issue) {
  return { status: 'error', reason: 'No issue id. Run /forge:work <issue-id>.' }
}

const increments =
  Array.isArray(input.increments) && input.increments.length
    ? input.increments.map((inc, i) => ({
        id: String(inc.id || i + 1),
        title: inc.title || '',
        criteria: Array.isArray(inc.criteria) ? inc.criteria : [],
        dependsOn: Array.isArray(inc.dependsOn) ? inc.dependsOn.map(String) : [],
        agent: inc.agent || 'forge:implementer',
      }))
    : [{ id: '1', title: '', criteria: [], dependsOn: [], agent: 'forge:implementer' }]

const RULES = [
  'You cannot ask the user anything. Decide and proceed.',
  'Use forge-test, forge-lint, forge-typecheck, forge-build. Never call the raw runners.',
  'Escalate detail only after a failure: bare command, then --failing, then --detail <id>.',
  'Return the requested object. No prose, no summary of your steps.',
].join('\n')

const criteriaLine = (inc) =>
  inc.criteria.length
    ? `Only these acceptance criteria are yours: ${inc.criteria.join(', ')}. The issue holds others; they belong to another increment and are not your scope.`
    : 'Every acceptance criterion in the issue is yours.'

// ---------------------------------------------------------------------------
phase('Prepare')

const prep = await agent(
  [
    `Prepare the run for issue ${issue}.`,
    '',
    `Create branch forge/${issue} from the current HEAD and switch to it. Change nothing else.`,
    'Return the branch name and the commit sha it was cut from.',
    '',
    RULES,
  ].join('\n'),
  { agentType: 'forge:implementer', schema: PREPARE, label: `prepare:${issue}`, phase: 'Prepare' },
)

if (!prep) {
  return {
    status: 'error',
    issue,
    reason:
      'Preparation returned nothing. Check that the plugin-scoped agent type forge:implementer ' +
      'resolves; if it does not, the run never started.',
  }
}

const issueBranch = prep.branch

// ---------------------------------------------------------------------------
// One increment: implement, review until the verdict converges, commit on its
// own branch.
//
// A worktree exists only to keep concurrent implementers off each other - two
// editing one checkout would overwrite each other. An uncut issue has nothing
// running beside it, so it works in the checkout on the issue branch directly:
// no worktree to create, none to clean up, and the common case stays cheap.
// ---------------------------------------------------------------------------
const solo = increments.length === 1

async function runIncrement(inc) {
  const label = solo ? issue : `${issue}/${inc.id}`
  const branch = solo ? issueBranch : `forge/${issue}/${inc.id}`
  const worktree = solo ? '' : `.claude/worktrees/forge-${issue}-${inc.id}`

  let run = await agent(
    [
      `Implement increment ${inc.id} of issue ${issue}.${inc.title ? ` ${inc.title}` : ''}`,
      '',
      'Steps:',
      `1. Read issue ${issue} through the project's issue-backend skill. It gives you a goal and`,
      '   acceptance criteria and nothing else - no file list, no plan. Finding your way is your job.',
      `2. ${criteriaLine(inc)}`,
      '3. Consult your memory before any search tool. It holds the project map you built on earlier',
      '   runs. Search only for what memory does not answer. As you write code, update your agent',
      '   memory with patterns, conventions, and recurring issues you discover.',
      ...(solo
        ? [`4. The checkout is already on ${branch}. Work there.`]
        : [
            '4. Create your workspace off the issue branch and work only inside it:',
            `     git branch ${branch} ${issueBranch}`,
            `     git worktree add ${worktree} ${branch}`,
            '   Prefix every command with a `cd` into that worktree.',
          ]),
      '5. Implement the change. Run forge-test once when you are done.',
      '',
      'Stage everything with `git add -A`. Do not commit.',
      'Staging is what makes your work visible to the review, new files included.',
      '',
      'Return status "blocked" with a blocker instead of guessing when the increment is unworkable.',
      solo
        ? 'Return an empty worktree path and the sha the branch was cut from.'
        : 'Return the absolute path of the worktree and the sha the branch was cut from.',
      '',
      RULES,
    ].join('\n'),
    { agentType: inc.agent, schema: RESULT, label: `implement:${label}`, phase: 'Implement' },
  )

  if (!run) return { inc, status: 'error', reason: 'Implementer returned nothing.' }
  if (run.status === 'blocked') return { inc, status: 'blocked', blocker: run.blocker || 'unspecified', branch }

  const wt = solo ? '' : run.worktree || worktree
  const base = run.base || prep.base
  const where = wt ? `cd ${wt} && ` : ''

  const reviewBrief = [
    wt
      ? `The work sits in the worktree ${wt}, on branch ${branch}, staged and uncommitted.`
      : `The work sits in the checkout, on branch ${branch}, staged and uncommitted.`,
    `The diff to judge is \`${where}git diff ${base}\`: everything this increment produced, new`,
    'files included. Use exactly that base; do not guess a base branch name.',
    ...(wt ? ['Run every check inside that worktree too. The main checkout does not carry this change.'] : []),
    '',
    `Read issue ${issue} yourself, through the project's issue-backend skill. Nobody hands you a`,
    'summary of the change - you have the issue and the diff, and that is the point.',
    `${criteriaLine(inc)}`,
    '',
    'A red check is a fact you report. It is a finding only if this change caused it. When the diff',
    `touched the failing code, prove it: \`git worktree add <tmp-dir> ${base}\`, run the same check`,
    'there, remove the worktree. Red at the base too means it was already broken - list it under',
    'preexisting and move on.',
    '',
    'You may write and run code to settle a doubt - a probe, a repro, a throwaway harness - but only',
    'inside a worktree you built outside the checkout. Writes into the checkout are refused. A probe',
    'that reaches the diff becomes a change no criterion asked for.',
  ].join('\n')

  let verdict = null
  let previousFailed = null
  let round = 0

  while (true) {
    // A fresh reviewer every round, with no memory, judging the whole
    // accumulated diff rather than the last round's increment. Judging only the
    // increment would report criteria an earlier round already satisfied as
    // unmet, and would miss a repair that broke one of them.
    verdict = await agent(
      [
        `Review increment ${inc.id} of issue ${issue}.`,
        '',
        reviewBrief,
        '',
        'Check every criterion that is yours, not only the ones that failed before - a repair can',
        'break a criterion that used to hold. Run each verify command the issue names.',
        'Judge only the criteria. Style opinions are out of scope.',
        'Set pass true only when every criterion of this increment holds.',
        '',
        RULES,
      ].join('\n'),
      { agentType: 'forge:reviewer', schema: VERDICT, label: `review:${label}:${round}`, phase: 'Review' },
    )

    if (!verdict) return { inc, status: 'error', reason: 'Reviewer returned no verdict.', branch, worktree: wt }
    if (verdict.pass) break

    const failed = [...(verdict.failed || [])].sort().join(',')

    if (failed === previousFailed) {
      log(`${label}: same criteria failing twice - stopping after ${round} rounds`)
      return { inc, status: 'stalled', branch, worktree: wt, rounds: round, verdict }
    }
    if (round >= maxRounds) {
      log(`${label}: hit the ${maxRounds}-round cap without converging`)
      return { inc, status: 'failed', branch, worktree: wt, rounds: round, verdict }
    }

    previousFailed = failed
    round++

    const repair = await agent(
      [
        `Repair round ${round} for increment ${inc.id} of issue ${issue}.`,
        '',
        wt ? `Work in ${wt}, on ${branch}. Do not create another worktree.` : `Work in the checkout, on ${branch}.`,
        `Fix only these criteria: ${(verdict.failed || []).join(', ')}.`,
        ...(verdict.notes || []).map((n) => `- ${n}`),
        '',
        "Each line above carries the reviewer's reproduction. Reproduce it before you change",
        'anything, so you fix the defect rather than the sentence describing it.',
        'Change nothing else. Re-run only the checks that cover these criteria.',
        'Stage with `git add -A`, do not commit.',
        '',
        RULES,
      ].join('\n'),
      { agentType: inc.agent, schema: RESULT, label: `repair:${label}:${round}`, phase: 'Implement' },
    )

    if (!repair) return { inc, status: 'error', reason: `Repair round ${round} returned nothing.`, branch, worktree: wt }
    if (repair.status === 'blocked') {
      return { inc, status: 'blocked', blocker: repair.blocker || 'unspecified', branch, worktree: wt }
    }
    run = { ...repair, worktree: wt, branch, base }
  }

  const commit = await agent(
    [
      `Commit increment ${inc.id} of issue ${issue}.`,
      '',
      wt
        ? `Commit inside ${wt}, which is checked out on ${branch}. Everything is staged.`
        : `Commit in the checkout, on ${branch}. Everything is staged.`,
      'Do not push. Do not open a pull request. Do not merge.',
      `Message: first line "${issue}: ${run.summary}", then a blank line, then one bullet per`,
      'acceptance criterion this increment met.',
      '',
      RULES,
    ].join('\n'),
    { agentType: inc.agent, schema: COMMIT, label: `commit:${label}`, phase: 'Commit' },
  )

  if (!commit || !commit.committed) {
    return { inc, status: 'uncommitted', branch, worktree: wt, rounds: round, summary: run.summary }
  }

  return {
    inc,
    status: 'accepted',
    branch,
    worktree: wt,
    sha: commit.sha || '',
    rounds: round,
    summary: run.summary,
    preexisting: verdict.preexisting || [],
  }
}

// ---------------------------------------------------------------------------
// Waves. An increment runs once every increment it depends on has merged, so a
// wave is a barrier by necessity. Within a wave the increments are independent
// by the cut's own assertion and run concurrently.
// ---------------------------------------------------------------------------
const pending = new Map(increments.map((inc) => [inc.id, inc]))
const mergedIds = new Set()
const outcomes = []

while (pending.size) {
  const ready = [...pending.values()].filter((inc) => inc.dependsOn.every((d) => mergedIds.has(d)))

  if (!ready.length) {
    for (const inc of pending.values()) {
      outcomes.push({ increment: inc.id, status: 'skipped', reason: 'a dependency did not merge' })
    }
    break
  }

  for (const inc of ready) pending.delete(inc.id)

  phase('Implement')
  const wave = (await parallel(ready.map((inc) => () => runIncrement(inc)))).filter(Boolean)

  const accepted = wave.filter((r) => r.status === 'accepted')
  for (const r of wave.filter((r) => r.status !== 'accepted')) {
    outcomes.push({
      increment: r.inc.id,
      status: r.status,
      branch: r.branch || '',
      worktree: r.worktree || '',
      rounds: r.rounds,
      failed: r.verdict ? r.verdict.failed : undefined,
      notes: r.verdict ? r.verdict.notes || [] : undefined,
      blocker: r.blocker,
      reason: r.reason,
    })
  }

  if (!accepted.length) continue

  // Merging is serialized: two merges into one branch cannot run at the same
  // time. A conflict is reported, never resolved - two agent-written changes to
  // the same lines are exactly where an automatic resolution would produce
  // something neither agent intended.
  phase('Merge')
  const merge =
    solo
      ? { results: [{ increment: accepted[0].inc.id, merged: true, sha: accepted[0].sha }] }
      : await agent(
          [
            `Merge accepted increments of issue ${issue} onto ${issueBranch}, in this order:`,
            ...accepted.map((r) => `  ${r.inc.id}: ${r.branch}`),
            '',
            `Switch the main checkout to ${issueBranch} and merge each branch in turn.`,
            'On a conflict: abort that merge, leave its branch untouched, record the conflict, and',
            'carry on with the next one. Never resolve a conflict yourself.',
            'After a branch merges cleanly, remove its worktree with `git worktree remove`.',
            'Leave the worktree of a branch that conflicted.',
            'Do not push.',
            '',
            RULES,
          ].join('\n'),
          { agentType: 'forge:implementer', schema: MERGE, label: `merge:${issue}`, phase: 'Merge' },
        )

  const byIncrement = new Map((merge && merge.results ? merge.results : []).map((r) => [String(r.increment), r]))

  for (const r of accepted) {
    const m = byIncrement.get(String(r.inc.id))
    if (m && m.merged) {
      mergedIds.add(r.inc.id)
      outcomes.push({
        increment: r.inc.id,
        status: 'merged',
        branch: r.branch,
        sha: m.sha || r.sha,
        rounds: r.rounds,
        summary: r.summary,
        preexisting: r.preexisting,
      })
    } else {
      outcomes.push({
        increment: r.inc.id,
        status: 'conflicted',
        branch: r.branch,
        worktree: r.worktree,
        rounds: r.rounds,
        conflict: m ? m.conflict || 'unspecified' : 'the merge step reported nothing for this increment',
      })
    }
  }
}

const merged = outcomes.filter((o) => o.status === 'merged')

return {
  status: merged.length === increments.length ? 'done' : merged.length ? 'partial' : 'failed',
  issue,
  branch: issueBranch,
  increments: outcomes,
}
