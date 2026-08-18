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

// A loop converges on `pass`, or stalls when a round repeats the previous
// round's failed set. MAX_ROUNDS is the backstop for a verdict that oscillates.
const MAX_ROUNDS = 8

// The reviewer reads the issue itself. Nothing the implementer wrote about its
// own work reaches it: an account of the change would be what it graded.
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

// A bare issue id is one increment covering every criterion.
const input = typeof args === 'string' ? { issue: args.trim() } : args || {}
const issue = input.issue ? String(input.issue).trim() : ''
const maxRounds = Number(input.maxRounds) > 0 ? Number(input.maxRounds) : MAX_ROUNDS

// Installed, the agents are namespaced `forge:`. Used directly from a checkout's
// .claude/agents/ they are not. Pass agentPrefix: '' for that.
const agentPrefix = typeof input.agentPrefix === 'string' ? input.agentPrefix : 'forge:'
const IMPLEMENTER = `${agentPrefix}implementer`
const REVIEWER = `${agentPrefix}reviewer`

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
        agent: inc.agent || IMPLEMENTER,
      }))
    : [{ id: '1', title: '', criteria: [], dependsOn: [], agent: IMPLEMENTER }]

// Everything else an agent works by is in the agent-protocol skill, preloaded
// into both. Repeating it here would only let the two drift apart.
const RULES = 'You cannot ask the user anything. Decide and proceed.'

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
  { agentType: IMPLEMENTER, schema: PREPARE, label: `prepare:${issue}`, phase: 'Prepare' },
)

if (!prep) {
  return {
    status: 'error',
    issue,
    reason:
      `Preparation returned nothing. Check that the agent type ${IMPLEMENTER} resolves; if it ` +
      'does not, the run never started.',
  }
}

const issueBranch = prep.branch

// A worktree exists only to keep concurrent implementers off each other. An
// uncut issue has none running beside it, so it works in the checkout: nothing
// to create, nothing to clean up.
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
      `1. Read issue ${issue} through the project's issue-backend skill. Goal and criteria only -`,
      '   no file list, no plan. Find your own way.',
      `2. ${criteriaLine(inc)}`,
      '3. Read your memory before any search tool. Search only what it does not answer.',
      ...(solo
        ? [`4. The checkout is already on ${branch}. Work there.`]
        : [
            '4. Create your workspace off the issue branch and work only inside it:',
            `     git branch ${branch} ${issueBranch}`,
            `     git worktree add ${worktree} ${branch}`,
            '   Prefix every command with a `cd` into that worktree.',
          ]),
      '5. Implement the change. Run forge-test once when you are done.',
      '6. Stage with `git add -A`. Do not commit. Unstaged files are invisible to the review.',
      '   Your memory file is part of the work: write it inside your workspace, never in the',
      '   main checkout, or it stays uncommitted.',
      '',
      'Return status "blocked" with a blocker rather than guessing where the increment is unworkable.',
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
    `The diff to judge is \`${where}git diff ${base}\`. Use exactly that base.`,
    ...(wt ? [`Run every check there too: \`${where}<command>\`. The main checkout lacks this change.`] : []),
    `Read issue ${issue} yourself, through the project's issue-backend skill.`,
    criteriaLine(inc),
    `Prove a red check at the base before filing it: \`git worktree add <tmp-dir> ${base}\`.`,
  ].join('\n')

  let verdict = null
  let previousFailed = null
  let round = 0

  while (true) {
    // A fresh reviewer each round, judging the whole accumulated diff. Judging
    // only the latest edit would miss a repair that broke an earlier criterion.
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
      { agentType: REVIEWER, schema: VERDICT, label: `review:${label}:${round}`, phase: 'Review' },
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
        'Reproduce each finding before you change anything.',
        'Change nothing else. Re-run only the checks covering these criteria.',
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
      wt ? `Commit inside ${wt}, on ${branch}. Everything is staged.` : `Commit in the checkout, on ${branch}.`,
      'Do not push. Do not merge.',
      `Message: "${issue}: ${run.summary}", a blank line, then one bullet per criterion met.`,
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

// An increment runs once everything it depends on has merged, so a wave is a
// barrier. Within a wave the cut asserts independence, so they run concurrently.
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

  // Serialized: two merges into one branch cannot run at once. A conflict is
  // reported, never resolved.
  phase('Merge')
  const merge =
    solo
      ? { results: [{ increment: accepted[0].inc.id, merged: true, sha: accepted[0].sha }] }
      : await agent(
          [
            `Merge accepted increments of issue ${issue} onto ${issueBranch}, in this order:`,
            ...accepted.map((r) => `  ${r.inc.id}: ${r.branch}`),
            '',
            `Switch the main checkout to ${issueBranch} and merge each in turn.`,
            'On a conflict: abort that merge, record it, carry on with the next. Never resolve one.',
            'Remove the worktree of each branch that merged cleanly. Leave the rest.',
            `If \`.claude/agent-memory/\` is dirty in the checkout afterwards, an implementer wrote`,
            `its memory outside its worktree. Commit it on ${issueBranch} as "${issue}: agent memory".`,
            'Do not push.',
            '',
            RULES,
          ].join('\n'),
          { agentType: IMPLEMENTER, schema: MERGE, label: `merge:${issue}`, phase: 'Merge' },
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
