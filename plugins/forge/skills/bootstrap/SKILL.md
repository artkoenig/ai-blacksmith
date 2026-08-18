---
name: bootstrap
description: Set up a project for forge - interview once, then write the issue backend adapter, the check commands, the rules and the settings. Use before the first /forge:issue or /forge:work in a repository.
argument-hint: "[no arguments]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Bootstrap a project for forge

Set this project up once. Interview the user, then write the files. Ask only what you cannot
determine yourself.

## 1. Look before you ask

Detect the stack and the commands first. Read `package.json` scripts, `pyproject.toml`,
`Makefile`, `go.mod`, `Cargo.toml`, or the CI workflow. Detect the issue backend: a `.github/`
directory with issues in use, an `issues/` or `docs/issues/` folder of markdown files, a
`.jira` config.

Propose what you found. Ask the user to confirm or correct it, in one round of questions:

- **Issue backend** - GitHub Issues, markdown files in the repo, or something else. If markdown,
  agree on the directory and the file naming.
- **Commands** - test, lint, typecheck, build. Any that do not exist stay empty.
- **Subset flag** - how the test runner runs a subset, for example `-t {pattern}` for jest,
  `-k {pattern}` for pytest, `-run {pattern}` for go.

## 2. Check the two preconditions

Both are load-bearing. Report each in one line, and say plainly what breaks if it is off.

- **Auto memory.** Read `autoMemoryEnabled` from the user and project settings and check
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY`. When auto memory is off, the agents' `memory:` field does
  nothing, agents relearn the project on every run, and the token budget will not hold.
- **Workflows.** `/forge:work` is a workflow. It needs Claude Code v2.1.154 or later and a paid
  plan; on Pro it must be enabled in `/config`. Without it there is no execution path at all.

## 3. Write the files

Write `.forge/config.json`:

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

`failingPattern` is only read by the `generic` parser: a grep extended regex whose match is the
identifier of one failure. Leave it empty when the built-in parser fits.

Then write, each from the matching file in `${CLAUDE_PLUGIN_ROOT}/templates/`:

- `.claude/skills/issue-backend/SKILL.md` from `issue-backend-skill.md`, with every placeholder
  replaced by a real command. Test each command once before you write it down.
- `.claude/rules/forge.md` from `forge-rules.md`. Keep it under 20 lines; it loads every session.

Merge into `.claude/settings.json` without discarding existing keys:

```json
{
  "env": { "BASH_MAX_OUTPUT_LENGTH": "8000" },
  "permissions": {
    "allow": ["Bash(forge-test:*)", "Bash(forge-lint:*)", "Bash(forge-typecheck:*)", "Bash(forge-build:*)"]
  }
}
```

Do not add deny rules for the raw runners. A deny rule is evaluated regardless of what the guard
hook returns, so it would block the rewrite the hook performs and cost a turn instead of saving one.

Append to `.gitignore`: `.forge/last/`, `.forge/metrics.jsonl`, `.claude/agent-memory-local/`.

Commit `.claude/agent-memory/`. That is the point of it: the agents' project knowledge is shared
through version control.

## 4. Verify, then report

Run `forge-test` once. It must print exactly `0` or `1`. If it prints anything else, the config is
wrong; fix it before reporting success.

Report in at most five lines: backend, commands wired, the two preconditions, and the next step
(`/forge:issue`).
