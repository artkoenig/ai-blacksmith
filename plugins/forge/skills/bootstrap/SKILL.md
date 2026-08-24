---
name: bootstrap
description: Set up a project for forge - detect the commands and the issue backend, then write the adapter, the check commands, the rules and the settings. Runs unattended where the repository answers, and asks only where it does not. On a project that does not exist yet it grills once instead, and comes out with the scaffold, the architecture and the first issues. Use before the first /forge:issue in a repository, and whenever a session finds the project unconfigured.
argument-hint: "[no arguments]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Bootstrap a project for forge

## 1. Detect, and decide what the repository answers

You may have been invoked with nobody asking - the session-start notice tells a session in an
unconfigured project to run you. So decide from the repository, and spend a question only on what
the repository genuinely leaves open.

Read `package.json` scripts, `pyproject.toml`, `Makefile`, `go.mod`, `Cargo.toml`, the Gradle or
Maven build files, or the CI workflow. Run every command before you write it down.

**Nothing to detect sends you to section 2.** A repository with no build system - a fresh checkout,
a project whose first source file is not written yet - has its answers in the human rather than in
the files. Never write a config from what you found there anyway: empty commands silence the
session-start notice for good, so the project that most needs setting up becomes the one that never
gets it.

**Issue backend.** The first that holds:

- an `issues/` or `docs/issues/` folder already in the repository - markdown, there, keeping the
  file naming in use;
- a GitHub remote, and GitHub tooling available in this session - GitHub Issues;
- neither - markdown in `docs/issues/`, named `<n>-<slug>.md`.

**Commands.** test, lint, typecheck, build, read off the build files. Leave any that does not exist
empty: an empty command answers `unconfigured`, which beats a command that does not run.

**Subset flag.** It follows from the runner - jest and vitest `-t {pattern}`, pytest `-k {pattern}`,
go `-run {pattern}`, cargo `{pattern}`, Gradle `--tests {pattern}`. Any other runner: read its
`--help`.

**Ask only where detection is genuinely ambiguous** - two test runners configured side by side with
nothing choosing between them, an issues folder and an active GitHub tracker both in use. One round,
carrying only the questions the repository left open. What you decided yourself goes in the report
instead, where it is cheap to correct.

## 2. A project that does not exist yet: grill once

Reaching here means the session is about to start something. Where nobody has said so - an empty
checkout and a request about something else entirely - stop and say nothing. An empty directory is
not a project, and a bootstrap nobody asked for is a round nobody gets back.

Where they have, ask once. One round settles what the rest of this skill would otherwise drag out of
the human a question at a time:

- **What is being built, and what the first version does.** The boundary of the MVP - what is in it,
  and what is deliberately left out. Everything below is cut from this answer.
- **Stack and language.** They decide the commands, the subset flag, and whether cast can read the
  project at all.
- **Layers.** The two to four names the code divides into, and which may depend on which. Ask it as
  a question about the project rather than about cast: what talks to the store, what draws the
  screen, what neither.
- **A user-facing surface?** Where there is one, the screens are worth drafting with the `design`
  skill before any issue is cut - a screen settles an argument that prose keeps open. Where there is
  none, do not raise it again.

Decide the issue backend from the remote, by section 1's order. Not everything is a question just
because the files are empty.

Then, in this order:

1. **Scaffold, minimally.** The build file, a directory per layer, and one real test that passes.
   Nothing else - features are what the issues are for. Skip it and every command in the config is
   one that has never run, and the wrappers answer `unconfigured` to the first agent that calls one.
2. **Section 4, against the scaffold.** The commands are real now, so run them, exactly as they are
   run for a project that already had code.
3. **The architecture, as an intention.** `.cast/layers.json` maps one glob per layer to its name,
   `.cast/rules.json` holds the dependencies those layers may not have. Globs describe the tree that
   is planned, so both are written before the code that fills them, and every increment is measured
   against them from the first. cast reads a language only through an adapter and ships few - where
   the project's has none, say so in one line: the layers are recorded, the check is unavailable
   until an adapter exists, and writing one is an issue of its own.
4. **The MVP issues.** Invoke the `forge:issue` skill once per item of the boundary. It carries the
   criteria discipline and decides the cut - repeating either here would be a second copy to
   maintain - and it does not re-ask what this interview settled.

## 3. Check the precondition

Report it in one line, and what breaks without it.

- **Workflows.** `/forge:work` is a workflow. Needs Claude Code v2.1.154 or later and a paid plan;
  on Pro, enabled in `/config`. Off means there is no execution path.

## 4. Write the files

`.forge/config.json`:

```json
{
  "version": 1,
  "commands": {
    "test": { "command": "<raw test command>", "parser": "jest|pytest|go|cargo|generic", "runArg": "-t {pattern}", "failingPattern": "", "passingPattern": "" },
    "lint": { "command": "<raw lint command>", "parser": "generic", "failingPattern": "", "passingPattern": "" },
    "typecheck": { "command": "<raw typecheck command>", "parser": "generic", "failingPattern": "", "passingPattern": "" },
    "build": { "command": "<raw build command>", "parser": "generic", "failingPattern": "", "passingPattern": "" }
  },
  "compaction": { "maxLines": 200, "maxChars": 10000 },
  "guard": { "rewrite": [] },
  "issueBackend": "<github|markdown|other>"
}
```

`failingPattern` and `passingPattern` are read by the `generic` parser only, both grep extended
regexes: the first matches one failure's identifier, the second one passing test. Without
`passingPattern` a green run answers `all tests succeeded` instead of `<n>/<n> tests succeeded`.
Leave both empty where a built-in parser fits - it counts on its own.

`compaction` bounds what a Bash command may spend. Past `maxLines` or `maxChars` its stdout is
withheld: the full text goes to `.forge/last/`, and only the size, that path and how to query it
come back. Under both, the output arrives untouched.

From `${CLAUDE_SKILL_DIR}`:

- `.claude/skills/issue-backend/SKILL.md` from `issue-backend-template.md`. Replace every
  placeholder with a real command. Run each one before you write it down.
- `.claude/rules/areas/` - one note per area of the codebase, written by the `forge:insights`
  skill. Seed the two or three areas the interview already named: run the skill once per
  directory, passing it that directory. The agents write the rest as they learn them.

Merge into `.claude/settings.json`, keeping existing keys:

```json
{
  "env": { "BASH_MAX_OUTPUT_LENGTH": "8000" },
  "permissions": {
    "allow": [
      "Bash(forge-test:*)", "Bash(forge-lint:*)", "Bash(forge-typecheck:*)", "Bash(forge-build:*)",
      "Bash(forge-context:*)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git add:*)", "Bash(git commit:*)",
      "Bash(git checkout:*)", "Bash(git branch:*)", "Bash(git rev-parse:*)", "Bash(git worktree:*)",
      "Bash(git merge:*)", "Bash(cd:*)"
    ]
  }
}
```

Every entry you drop turns into a prompt mid-run. `git worktree` is on the list because the reviewer
runs checks at the base commit, and because cut issues get a worktree per increment.

Never add deny rules for the raw runners. A deny rule is evaluated whatever the guard hook returns,
so it blocks the rewrite instead of saving a turn.

Append to `.gitignore`: `.forge/last/`, `.forge/metrics.jsonl`, `.forge/context.jsonl`,
`.forge/context/`, `.claude/worktrees/`.

The rules forge itself works by are not written into the project. The plugin injects them at
every session start, so a plugin update carries them - never copy them into `.claude/rules/`.
What belongs there is this project's own knowledge, one topic per file.

`.claude/rules/` is committed. That is how project knowledge reaches an agent. Prove it is not
ignored:

```bash
git check-ignore -v .claude/rules/probe.md
```

Anything printed names the rule that swallows it - usually a blanket `.claude/`. Append
`!.claude/rules/` and check again.

## 5. Verify, then report

Run `forge-test`. A green project answers one line and exits `0`; a red one lists its failures and
exits `1`. Exit `2` means the config is wrong - fix it before reporting success.

Report in five lines at most: backend, commands wired, the two preconditions, next step
(`/forge:issue`, or `/forge:work` where section 2 already wrote the issues - name them and their
ids). Say which of it you decided rather than asked, so a wrong call is cheap to correct. Where the
session-start notice invoked you rather than the human, stop there and get on with the work the
session was opened for - unless that work was the project itself, which section 2 has just set up.
