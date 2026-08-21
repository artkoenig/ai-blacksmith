---
name: issue
description: Interview the user, write one issue with verifiable acceptance criteria, and decide whether to cut it into increments. Use when the user wants to capture work, plan a change, or file a ticket. The run starts later, on request.
argument-hint: "[short description of the work]"
allowed-tools: AskUserQuestion, Read, Write, Bash, Skill
---

# Write an issue

## 1. Interview

Ask only what changes the outcome, in as few rounds as possible:

- What is true when this is done? One sentence.
- How would you check it? Push for something runnable.
- What must not change?

Never ask what the codebase answers.

## 2. Write it

Use `${CLAUDE_SKILL_DIR}/issue-template.md`. The issue holds a goal, its acceptance criteria,
and what is out of scope. Nothing else: no file paths, no line ranges, no plan, no agent.

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

You have no search tools here. The implementer finds its own way. A map written into an issue is
maintained by nobody.

Persist through the project's `issue-backend` skill. Where it does not exist, stop and say
`/forge:bootstrap` has not run.

## 3. Decide the cut

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

## 4. Hand it over

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
