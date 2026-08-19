---
name: bootstrap
description: Set up a project for forge - interview once, then write the issue backend adapter, the check commands, the rules and the settings. Use before the first /forge:issue in a repository.
argument-hint: "[no arguments]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Bootstrap a project for forge

## 1. Detect, then confirm

Read `package.json` scripts, `pyproject.toml`, `Makefile`, `go.mod`, `Cargo.toml` or the CI
workflow. Look for the issue backend: issues in use on GitHub, an `issues/` or `docs/issues/`
folder, a `.jira` config.

Propose what you found. Ask the user to confirm or correct it in one round:

- **Issue backend** - GitHub Issues, markdown files, or other. For markdown, settle directory and
  file naming.
- **Commands** - test, lint, typecheck, build. Leave any that do not exist empty.
- **Subset flag** - how the test runner takes a pattern: `-t {pattern}`, `-k {pattern}`,
  `-run {pattern}`.

## 2. Check the precondition

Report it in one line, and what breaks without it.

- **Workflows.** `/forge:work` is a workflow. Needs Claude Code v2.1.154 or later and a paid plan;
  on Pro, enabled in `/config`. Off means there is no execution path.

## 3. Write the files

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
- `.claude/rules/forge.md` from `rules-template.md`. It loads every session.
- `.claude/rules/areas/` - one note per area of the codebase, from `area-note-template.md`. Each
  carries a `paths:` glob and loads only when an agent reads a file it matches, so an area costs
  nothing until it is worked in. Seed the two or three areas the interview already named; the
  agents write the rest as they learn them.

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

`.claude/rules/` is committed. That is how project knowledge reaches an agent. Prove it is not
ignored:

```bash
git check-ignore -v .claude/rules/probe.md
```

Anything printed names the rule that swallows it - usually a blanket `.claude/`. Append
`!.claude/rules/` and check again.

## 4. Verify, then report

Run `forge-test`. A green project answers one line and exits `0`; a red one lists its failures and
exits `1`. Exit `2` means the config is wrong - fix it before reporting success.

Report in five lines at most: backend, commands wired, the two preconditions, next step
(`/forge:issue`).
