---
name: issue
description: Interview the user, write one issue with verifiable acceptance criteria, decide whether to cut it into increments, and start the run. Use when the user wants to capture work, plan a change, or file a ticket.
argument-hint: "[short description of the work]"
allowed-tools: AskUserQuestion, Read, Write, Bash, Skill
---

# Write an issue and start the run

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

You have no search tools here. The implementer finds its own way. A map written into an issue is
maintained by nobody.

Persist through the project's `issue-backend` skill. Where it does not exist, stop and say
`/forge:bootstrap` has not run.

## 3. Decide the cut

You are the only place that sees the whole issue at once. Decide now.

**What an increment costs.** Three agent dispatches as a floor - implement, review, commit - plus
two per repair round, plus a share of the merge. Every dispatch re-pays a fresh system prompt, the
CLAUDE.md hierarchy and the project rules. A cut adds a dispatch set. It halves nothing.

**Cut only where one holds:**

- the parts have no dependency between them and run in parallel;
- one diff would be too large to review in a single pass;
- one part must land and be verified before the next is built on it.

**Never cut:**

- criteria that touch the same code - that buys merge conflicts and double review;
- an issue with two or three criteria;
- an increment carrying one trivial criterion.

**Dependencies are your assertion.** Nothing proves two increments disjoint. Assert independence
only where the criteria are about different things. A wrong call surfaces as a merge conflict.

## 4. Start the run

Invoke `/forge:work` with the issue id, or with the cut:

```
{ issue: "<id>", increments: [
  { id: "a", title: "…", criteria: ["AC1", "AC2"], dependsOn: [] },
  { id: "b", title: "…", criteria: ["AC3"], dependsOn: ["a"], agent: "project:api" }
]}
```

`agent` is optional and names a project agent for that increment.

Do not ask for approval. The run pushes nothing and opens nothing.

Report the issue id, one line per criterion, one line per increment. Nothing else.
