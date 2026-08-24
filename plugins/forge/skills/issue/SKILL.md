---
name: issue
description: Interview the user, write one issue with verifiable acceptance criteria, and decide whether to cut it into increments. Use when the user wants to capture work, plan a change, or file a ticket. The run is left for the user to invoke.
argument-hint: "[short description of the work]"
allowed-tools: AskUserQuestion, Read, Write, Bash, Skill, Agent(Explore)
---

# Write an issue

## 1. Ground it

Find out what the codebase already answers, before the first question reaches the user.

One dispatch of the built-in `Explore` agent does it. It is read-only, it searches broadly, and it
returns the finding rather than the files it read - so this context stays free for the issue. Ask
it for what the interview would otherwise ask the user:

- what the behaviour is today, at the sites the request names, with `path:line` for each;
- whether what is asked for exists already, in part or under another name;
- which command exercises that behaviour.

Give it the request verbatim and a breadth - `medium`, or `very thorough` where the request spans
several areas. Ask for prose and file references, nothing else.

**Why a dispatch here.** Asking the user first spends a round on what a search answers, and buys a
memory instead of the code. Searching from this session instead puts every excerpt into the one
context that has to hold the whole issue at once - which is why this skill has no search tool of
its own. Leaving it to the implementer is too late: the criteria and the cut are decided here, so a
wrong assumption about today's behaviour survives into the diff.

Skip it only where there is nothing to find - a greenfield project, a file that does not exist yet.
Say that you skipped it.

## 2. Interview

Ask only what the grounding left open, in as few rounds as possible:

- What is true when this is done? One sentence.
- How would you check it? Push for something runnable.
- What must not change?

Where the work adds or changes something a person looks at - a screen, a page, a control - carry
one more question in the same round: should a mockup be drafted with the `design` skill first? Ask
it alongside the questions above, never as a round of its own. Work that only changes what a
terminal prints - a command's output, a log line, an exit code - has nothing to draw, so the
question does not come up there.

Never ask what the codebase answers, and never ask again what a bootstrap interview settled
earlier in this session - it grilled for exactly these answers. Where the grounding contradicts the user, put the finding to
them with its `path:line` rather than asking the question again.

## 3. Draft the mockup

Only on a yes to that question, and before a line of the issue is written. Invoke the `design`
skill with what the interview settled: the screens or controls the work adds, what each one is for,
and the states that have to be visible. It comes back with a canvas the user can open and refine.

Drawing it first is what makes the criteria specific - what the screen shows becomes something the
issue can assert, instead of a sentence about a screen nobody has seen. The canvas is the one
reference the criteria are written against, so it goes in the issue's own `## Mockup` section.

On a no, on work with nothing to draw, or where the `design` skill is not installed, skip this and
go on.

## 4. Write it

Use `${CLAUDE_SKILL_DIR}/issue-template.md`. The issue holds a goal, the mockup where one was
drafted, its acceptance criteria, and what is out of scope. Nothing else: no file paths, no line
ranges, no plan, no agent.

- Fill `## Mockup` with the published link the `design` skill came back with, and nothing else.
  Where no canvas was drafted, drop the section - an empty heading reads as a mockup that went
  missing.
- Number the criteria `AC1`, `AC2`, … One verifiable statement each.
- Append `| verify: <command>` wherever a command decides it. Prefer `forge-test --run <pattern>`.

**A verify command is checked for red, never for whether it can go green.** Scope each one until
its red comes only from the code the criterion is about. Anything else it can match is a false red
that survives the work and reads as a failure nobody caused. Scope it and run it now:

- a `grep` over `docs/` matched the issue's own text - exclude the issue file, or point the grep at
  the directory the criterion is about;
- `ls a b` exits non-zero when either path is missing, so it cannot say which - one command per
  path, or a check that names the one it found missing;
- a `grep` over `src/ui` matched i18n strings and fixtures - narrow the glob, or match the call
  site rather than the string.

What the grounding found shapes the criteria and their verify commands. It does not go into the
issue. The implementer finds its own way. A map written into an issue is maintained by nobody.

Persist through the project's `issue-backend` skill. Where it does not exist, invoke the
`forge:bootstrap` skill and then persist - an issue that cannot be stored was written for nothing.
Where bootstrap writes no config because the project has nothing to detect yet, say that and stop.

## 5. Decide the cut

You are the only place that sees the whole issue at once. Decide now.

**What an increment costs.** Two agent dispatches as a floor - implement, review - plus one per
repair round. Every dispatch re-pays a fresh system prompt, the CLAUDE.md hierarchy and the project
rules. A cut adds a dispatch set, and its reviews run one after another. It halves nothing.

**Cut only where one holds:**

- the parts have no dependency between them and run in parallel;
- one diff would be too large to review in a single pass;
- one part must land and be verified before the next is built on it.

**Never cut:**

- criteria that touch the same code - that buys merge conflicts and double review;
- an issue with two or three criteria;
- an increment carrying one trivial criterion;
- a criterion that is a repo-wide invariant over N independent sites - it touches every increment's
  code at once, so no cut makes the parts disjoint. Keep it whole.

**Dependencies are your assertion.** Nothing proves two increments disjoint. Assert independence
only where the criteria are about different things. A wrong call surfaces as a merge conflict.

## 6. Hand it over

Start nothing. Filing an issue is not asking for it to be built: a run spends agent dispatches, and
when to pay them is the user's call. Never invoke `/forge:work` off the back of writing an issue.

Report the issue id, one line per criterion, one line per increment, and last the invocation that
starts it, verbatim, for the user to run when they want it:

```
/forge:work { "issue": "<id>", "increments": [
  { "id": "a", "title": "…", "criteria": ["AC1", "AC2"], "dependsOn": [] },
  { "id": "b", "title": "…", "criteria": ["AC3"], "dependsOn": ["a"], "agent": "project:api" }
]}
```

`agent` is optional and names a project agent for that increment. Where you did not cut, the
invocation is the bare id: `/forge:work <id>`.

Only where the user asks for the run in the same breath - "and build it", "start it" - invoke it
then, with that cut. Their request is the approval; do not ask for another.
