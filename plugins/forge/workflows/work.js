export const meta = {
  name: 'work',
  description: 'Implement one issue autonomously - one loop per increment, in parallel where the cut allows',
  whenToUse:
    'Run /forge:work <issue-id> to execute an issue written by /forge:issue, or pass a cut to run its increments. No user interaction is possible during the run.',
  phases: [
    { title: 'Implement', detail: 'a worktree per increment where the issue was cut' },
    { title: 'Review', detail: 'judge each increment, and merge the one that holds' },
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
    sha: { type: 'string', description: 'the commit this round produced, empty when blocked' },
    issueBranch: { type: 'string', description: 'branch the checkout was on before you cut yours' },
    summary: { type: 'string', description: 'the one line the user sees while the run goes on: what changed and that the checks are green, or what went wrong' },
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
    observations: {
      type: 'array',
      items: { type: 'string' },
      description: 'true remarks that block nothing - every criterion still met, no behaviour changed',
    },
    merged: { type: 'boolean', description: 'true when you landed the increment, false when you could not' },
    sha: { type: 'string', description: 'what the issue branch points at after you landed it' },
    resolution: { type: 'string', description: 'how you resolved a conflict, empty when there was none' },
    conflict: { type: 'string', description: 'what you could not resolve, empty when it merged' },
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


// A worktree exists only to keep concurrent implementers off each other. An
// uncut issue has none running beside it, so it works in the checkout: nothing
// to create, nothing to clean up.
const solo = increments.length === 1

async function runIncrement(inc) {
  const label = solo ? issue : `${issue}/${inc.id}`
  const branch = solo ? '' : `forge/${issue}/${inc.id}`
  const worktree = solo ? '' : `.claude/worktrees/forge-${issue}-${inc.id}`

  let run = await agent(
    [
      `Implement increment ${inc.id} of issue ${issue}.${inc.title ? ` ${inc.title}` : ''}`,
      '',
      'Steps:',
      `1. Read issue ${issue} through the project's issue-backend skill. Goal and criteria only -`,
      '   no file list, no plan. Find your own way.',
      `2. ${criteriaLine(inc)}`,
      '3. Read the project rules before any search tool. Search only what they do not answer.',
      ...(solo
        ? ['4. The checkout is already on the issue branch. Work there. Cut no branch.']
        : [
            '4. Create your workspace off the checkout\'s current branch and work only inside it:',
            `     git worktree add ${worktree} -b ${branch} HEAD`,
            '   Prefix every command with a `cd` into that worktree.',
          ]),
      '5. Implement the change. Run forge-test once when you are done.',
      `6. Commit: \`git add -A\`, message "${issue}: <what changed>", a blank line, then one bullet`,
      '   per criterion met. Unstaged work is invisible to the review. Do not push. Do not merge.',
      '',
      'Return status "blocked" with a blocker rather than guessing where the increment is unworkable.',
      solo
        ? 'Return an empty worktree path, the sha the branch was cut from, and the sha you committed.'
        : 'Return the worktree path, the branch the checkout was on before you cut yours, the sha the'
          + ' branch was cut from, and the sha you committed.',
      '',
      RULES,
    ].join('\n'),
    { agentType: inc.agent, schema: RESULT, label: `implement:${label}`, phase: 'Implement' },
  )

  if (!run) return { inc, status: 'error', reason: 'Implementer returned nothing.' }
  if (run.status === 'blocked') {
    log(`${label}: blocked - ${run.blocker || 'unspecified'}`)
    return { inc, status: 'blocked', blocker: run.blocker || 'unspecified', branch }
  }
  if (!run.sha) {
    log(`${label}: nothing committed - ${run.summary}`)
    return { inc, status: 'uncommitted', branch, summary: run.summary }
  }
  log(`${label}: ${run.summary}`)

  const wt = solo ? '' : run.worktree || worktree
  const base = run.base || 'HEAD'
  // The main worktree is listed first, so its branch is the issue branch. Only
  // needed when the implementer did not report the branch it cut from.
  const issueBranch =
    run.issueBranch ||
    "$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p' | head -1)"
  const where = wt ? `cd ${wt} && ` : ''

  const reviewBrief = [
    wt
      ? `The work is committed in the worktree ${wt}, on branch ${branch}.`
      : 'The work is committed in the checkout, on its current branch.',
    `The diff to judge is \`${where}git diff ${base}\`. Use exactly that base.`,
    ...(wt ? [`Run every check there too: \`${where}<command>\`. The main checkout lacks this change.`] : []),
    `Read issue ${issue} yourself, through the project's issue-backend skill.`,
    criteriaLine(inc),
    `Prove a red check at the base before filing it: \`git worktree add <tmp-dir> ${base}\`.`,
    'File nothing you cannot reproduce. A true remark that blocks nothing goes in `observations`.',
    'Answer the blast radius too: what this change breaks that no criterion names.',
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
        ...(wt
          ? [
              '',
              'When - and only when - you pass it, land it. Everything below happens inside your',
              'worktree. The main checkout has the issue branch checked out; writing there while',
              'another reviewer does the same collides on one index and one HEAD.',
              `  cd ${wt}`,
              `  ib=${issueBranch}`,
              '  tip=$(git rev-parse $ib)   # another reviewer may have landed since you started',
              '  git rebase $tip',
              '  <re-run the checks>',
              '  git update-ref refs/heads/$ib $(git rev-parse HEAD) $tip',
              'The update fails when someone landed between your rebase and it. That is not an error:',
              'read the tip again, rebase again, re-check, retry.',
              'A rebase conflict is two changes to one place, not a choice between them: resolve it so',
              'both sides keep working, and report how. Only where the sides contradict each other, so',
              'that keeping one drops what the other does, `git rebase --abort` and report merged false',
              `with what conflicted. When it landed, remove your worktree: \`git worktree remove ${wt}\`.`,
              'Report merged true and the sha the issue branch now points at.',
            ]
          : ['', 'The work is already on the issue branch. Land nothing. Report merged true when you pass it.']),
        '',
        RULES,
      ].join('\n'),
      { agentType: REVIEWER, schema: VERDICT, label: `review:${label}:${round}`, phase: 'Review' },
    )

    if (!verdict) return { inc, status: 'error', reason: 'Reviewer returned no verdict.', branch, worktree: wt }

    if (verdict.pass) {
      log(
        verdict.merged === false
          ? `${label}: passed, but the merge conflicted - ${verdict.conflict || 'unspecified'}`
          : `${label}: passed, landed`,
      )
      break
    }
    log(
      `${label}: rejected - ${(verdict.failed || []).join(', ') || 'no criterion named'}`
        + ((verdict.notes || []).length ? ` - ${verdict.notes.join('; ')}` : ''),
    )

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
        'Commit the repair on top: `git add -A`, subject `' + issue + ': <what the repair fixed>`.',
        '',
        RULES,
      ].join('\n'),
      { agentType: inc.agent, schema: RESULT, label: `repair:${label}:${round}`, phase: 'Implement' },
    )

    if (!repair) return { inc, status: 'error', reason: `Repair round ${round} returned nothing.`, branch, worktree: wt }
    if (repair.status === 'blocked') {
      log(`${label}: blocked in repair ${round} - ${repair.blocker || 'unspecified'}`)
      return { inc, status: 'blocked', blocker: repair.blocker || 'unspecified', branch, worktree: wt }
    }
    if (!repair.sha) {
      log(`${label}: repair ${round} committed nothing - ${repair.summary}`)
      return { inc, status: 'uncommitted', branch, worktree: wt, rounds: round, summary: repair.summary }
    }
    log(`${label}: repair ${round} - ${repair.summary}`)
    run = { ...repair, worktree: wt, branch, base }
  }

  return {
    inc,
    status: verdict.merged === false ? 'conflicted' : 'merged',
    branch,
    worktree: wt,
    sha: run.sha,
    conflict: verdict.merged === false ? verdict.conflict || 'unspecified' : undefined,
    resolution: verdict.resolution || undefined,
    landed: verdict.sha || undefined,
    rounds: round,
    summary: run.summary,
    preexisting: verdict.preexisting || [],
    observations: verdict.observations || [],
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

  for (const r of wave) {
    if (r.status === 'merged') mergedIds.add(r.inc.id)
    outcomes.push({
      increment: r.inc.id,
      status: r.status,
      branch: r.branch || '',
      worktree: r.worktree || '',
      sha: r.sha,
      rounds: r.rounds,
      summary: r.summary,
      failed: r.verdict ? r.verdict.failed : undefined,
      notes: r.verdict ? r.verdict.notes || [] : undefined,
      blocker: r.blocker,
      conflict: r.conflict,
      resolution: r.resolution,
      landed: r.landed,
      reason: r.reason,
      preexisting: r.preexisting,
      observations: r.observations,
    })
  }
}

const merged = outcomes.filter((o) => o.status === 'merged')

return {
  status: merged.length === increments.length ? 'done' : merged.length ? 'partial' : 'failed',
  issue,
  increments: outcomes,
  // An increment lands from its own worktree, so the issue branch moves while
  // the main checkout's files stay where they were. Whoever called the run
  // refreshes it: `git reset --hard`, once, after the last wave.
  checkout: solo || !merged.length ? 'current' : 'stale',
}
