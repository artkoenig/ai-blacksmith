# Developing forge

`plugins/forge/` is the source. The repository is set up to build forge with forge: `.claude/`
symlinks the components into project scope, so a session at the repo root uses them directly as
skills and agents, from the working tree.

```
.claude/agents/*.md          -> plugins/forge/agents/*.md
.claude/skills/*             -> plugins/forge/skills/*
.claude/workflows/work.js    -> plugins/forge/workflows/work.js
.claude/output-styles/*      -> plugins/forge/output-styles/*
.claude/settings.json         registers the hooks by path
.claude/skills/issue-backend  this repository's own adapter - GitHub Issues, not a symlink
.claude/rules/*.md            what every agent starts with
.claude/rules/areas/*.md      what is true of one directory, loaded when a file there is read
.forge/config.json            forge-test runs test.sh
.forge/context.jsonl          one line per agent start, plus copies under .forge/context/ (both ignored)
```

Edit the file under `plugins/forge/`. Never edit through the symlink path.

## Where the knowledge is

This page is the orientation. What you need while changing something reaches you on its own: each
area of the repository carries a note under `.claude/rules/areas/`, and the note arrives the first
time you read a file its `paths:` glob matches. So this page stays short on purpose - a fact that
belongs to one directory belongs in that directory's note, not here.

| Area | Note |
| --- | --- |
| `plugins/forge/scripts/**` | hook contract, double registration, where an agent's transcript lives |
| `plugins/forge/bin/**` | the `0`/`1` wrapper contract, `.forge/config.json`, the fixture |
| `plugins/forge/agents/**`, `plugins/forge/skills/**` | front matter, `${CLAUDE_SKILL_DIR}`, what is live |
| `plugins/forge/workflows/**` | the run loop, `agentPrefix`, the outcomes the control flow owes |
| `plugins/forge/output-styles/**` | why a style needs `/clear` |
| `.claude/rules/**` | how a rule loads, and what a note must satisfy |
| `test.sh` | the suite format, the fixtures, the seven suites |

`.claude/rules/areas/rules-and-notes.md` carries the measurements behind all of this: which tool
call loads a note and which does not, verified on 2.1.234.

## Names lose the `forge:` prefix

Used directly rather than installed, the components are project-scope:

| Installed | Here |
| --- | --- |
| `/forge:issue` | `/issue` |
| `/forge:work` | `/work` |
| `forge:implementer` | `implementer` |

So run the workflow with `agentPrefix: ""`:

```
/work {"issue": "3", "agentPrefix": ""}
```

## Checks

```bash
./test.sh          # seven suites, no Claude Code session needed
forge-test         # the same, through the wrapper: 0 or 1
```

## Still unverified

Neither has been observed in a real session:

- Whether `agentType: 'forge:implementer'` resolves a plugin-scoped agent inside a workflow. Here
  the unprefixed names are used instead, so this stays open until someone runs an installed copy.
- Whether plugin hooks fire inside workflow-spawned agents. Here the hooks come from project
  settings rather than the plugin, so this stays open too.
