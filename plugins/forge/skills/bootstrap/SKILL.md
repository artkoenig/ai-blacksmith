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

## 2. Check two preconditions

Report each in one line, and what breaks without it.

- **Auto memory.** Read `autoMemoryEnabled` from user and project settings, check
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY`. Off means the agents' `memory:` field does nothing and they
  relearn the project every run.
- **Workflows.** `/forge:work` is a workflow. Needs Claude Code v2.1.154 or later and a paid plan;
  on Pro, enabled in `/config`. Off means there is no execution path.

## 3. Write the files

`.forge/config.json`:

```json
{
  "version": 1,
  "commands": {
    "test": { "command": "<raw test command>", "parser": "jest|pytest|go|cargo|generic", "runArg": "-t {pattern}", "failingPattern": "" },
    "lint": { "command": "<raw lint command>", "parser": "generic", "failingPattern": "" },
    "typecheck": { "command": "<raw typecheck command>", "parser": "generic", "failingPattern": "" },
    "build": { "command": "<raw build command>", "parser": "generic", "failingPattern": "" }
  },
  "compaction": { "maxLines": 60, "headLines": 30, "tailLines": 15 },
  "guard": { "rewrite": [] },
  "issueBackend": "<github|markdown|other>"
}
```

`failingPattern` is read by the `generic` parser only: a grep extended regex whose match is one
failure's identifier. Leave it empty where a built-in parser fits.

From `${CLAUDE_SKILL_DIR}`:

- `.claude/skills/issue-backend/SKILL.md` from `issue-backend-template.md`. Replace every
  placeholder with a real command. Run each one before you write it down.
- `.claude/rules/forge.md` from `rules-template.md`. It loads every session.

Merge into `.claude/settings.json`, keeping existing keys:

```json
{
  "env": { "BASH_MAX_OUTPUT_LENGTH": "8000" },
  "permissions": {
    "allow": [
      "Bash(forge-test:*)", "Bash(forge-lint:*)", "Bash(forge-typecheck:*)", "Bash(forge-build:*)",
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

Append to `.gitignore`: `.forge/last/`, `.forge/metrics.jsonl`, `.claude/agent-memory-local/`,
`.claude/worktrees/`.

Commit `.claude/agent-memory/`. That is how agent knowledge is shared.

## 4. Verify, then report

Run `forge-test`. It prints exactly `0` or `1`. Anything else means the config is wrong - fix it
before reporting success.

Report in five lines at most: backend, commands wired, the two preconditions, next step
(`/forge:issue`).
