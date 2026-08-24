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
- **Commands** - test, lint, typecheck, build, deps. Leave any that do not exist empty. A project
  that carries a `.cast` directory has a dependency check already: wire `deps` to `cast-check`.
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
    "build": { "command": "<raw build command>", "parser": "generic", "failingPattern": "", "passingPattern": "" },
    "deps": { "command": "cast-check", "parser": "generic", "failingPattern": "", "passingPattern": "" }
  },
  "compaction": { "maxLines": 200, "maxChars": 10000 },
  "guard": { "rewrite": [] },
  "issueBackend": "<github|markdown|other>"
}
```

`commands.deps` is the dependency check, and `cast-check` is what a project carrying a `.cast`
directory wires it to: it scans and evaluates `.cast/rules.json` on the wrapper contract, so
`forge-deps` answers like every other check. A project without a `.cast` directory leaves `deps`
empty.

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
      "Bash(forge-deps:*)", "Bash(forge-context:*)",
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

## 4. Verify, then report

Run `forge-test`. A green project answers one line and exits `0`; a red one lists its failures and
exits `1`. Exit `2` means the config is wrong - fix it before reporting success.

Report in five lines at most: backend, commands wired, the two preconditions, next step
(`/forge:issue`).
