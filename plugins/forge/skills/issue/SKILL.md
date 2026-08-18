---
name: issue
description: Interview the user, write one issue with verifiable acceptance criteria, decide whether it can be cut into increments, and start the run. Use when the user wants to capture work, plan a change, or file a ticket.
argument-hint: "[short description of the work]"
allowed-tools: AskUserQuestion, Read, Write, Bash, Skill
---

# Write an issue and start the run

You are interviewing a human who is present right now. That is the one moment when asking is
cheaper than guessing.

## 1. Interview

Start from what the user said. Ask only what changes the outcome, in as few rounds as possible:

- What is true when this is done? One sentence.
- How would you check it? Push for something runnable. A criterion nobody can check is a criterion
  the reviewer will fail.
- What must not change?

Do not ask what you can read from the codebase.

## 2. Write it

The issue holds a goal, its acceptance criteria, and what is out of scope. Nothing else. No file
paths, no line ranges, no plan, no agent to use. Use
`${CLAUDE_PLUGIN_ROOT}/templates/issue.md` verbatim as the structure:

- **Goal** - one sentence.
- **Acceptance criteria** - numbered `AC1`, `AC2`, … Each is one verifiable statement. Append
  `| verify: <command>` wherever a command can decide it, preferring
  `forge-test --run <pattern>`.
- **Out of scope** - what must not change.

You have no search tools here, on purpose. An issue enriched with a file list is an issue that
rots: the next person to touch that area moves the code, and the run then trusts a map of somewhere
the change no longer lives. The implementer finds its own way, from the project map in its memory,
and writes back what it learns. That map is maintained by the runs that use it; a `Context` block
in an issue is maintained by nobody.

Persist through the project's `issue-backend` skill. If that skill does not exist, stop and say
`/forge:bootstrap` has not run.

## 3. Decide the cut

Now decide whether the issue runs as one increment or several. You are the only one who can: you
have just settled the criteria, and no agent downstream sees the whole issue at once.

**What an increment costs.** Every increment costs a floor of three agent dispatches - implement,
review, commit - plus two per repair round, plus a share of the merge. Every dispatch re-pays a
fresh system prompt, the CLAUDE.md hierarchy, and the agent's memory index before it does any work
at all. Cutting an issue in two does not halve anything; it adds a whole dispatch set. The instinct
to cut finely is exactly wrong here.

**Cut only when at least one of these holds:**

- the increments have no dependency between them and can run **in parallel**, so the extra
  dispatches buy wall-clock and two small diffs instead of one large one;
- the whole issue's diff would be too large for one reviewer to judge in a single pass;
- one part has to land and be verified before the next can be built on it.

**Do not cut** when the criteria all touch the same code - that buys merge conflicts and the same
files reviewed twice. Do not cut an issue with two or three criteria. Never leave an increment
carrying one trivial criterion.

**Dependencies are your judgment, not a derived fact.** With no file list in the issue, nothing
proves two increments disjoint. You assert it, and the run parallelizes on that assertion. Assert
it only where the criteria are about different things; a pair you call independent that in fact
touches the same code surfaces later as a merge conflict, which costs a human a resolution.

## 4. Start the run

Invoke `/forge:work` with the issue id when you did not cut, or with the cut when you did:

```
{ issue: "<id>", increments: [
  { id: "a", title: "…", criteria: ["AC1", "AC2"], dependsOn: [] },
  { id: "b", title: "…", criteria: ["AC3"], dependsOn: ["a"], agent: "project:api" }
]}
```

`agent` is optional and names a project agent for that increment; leave it out for
`forge:implementer`.

Do not ask for approval first. The run pushes nothing and opens nothing, so the worst case is a
branch to throw away - and a confirmation step on every issue costs more than that over time.

Report the issue id, one line per acceptance criterion, and one line per increment saying what it
covers and what it waits for. Nothing else.
