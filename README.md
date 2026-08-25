# ai-blacksmith

A Claude Code plugin marketplace, and the two plugins it ships.

```
/plugin marketplace add artkoenig/ai-blacksmith
/plugin install forge@artkoenig-marketplace
/plugin install cast@artkoenig-marketplace
```

Install at user scope - a project-scope plugin loads only after the workspace trust dialog.

What each plugin does is defined in its own README, and only there. This one says what is in the
repository and how to work on it; a copy of the rest would drift.

## The plugins

| Plugin | What it is | Read |
| --- | --- | --- |
| forge | Interview issues into shape, then execute them autonomously on the smallest token budget that works. `/forge:issue` writes the issue, `/forge:work` runs it as a loop of implement and review. | `plugins/forge/README.md` |
| cast | The module graph of a project, and what is wrong with it - cycles, layers, forbidden edges, and what a refactoring would change before a file is touched. | `plugins/cast/README.md` |

Both are MIT and carry no version: each is released from the tip of `main`, so the commit is the
version (`test.sh:12-14`).

## Layout

```
.claude-plugin/marketplace.json   the marketplace entry both plugins are installed from
plugins/forge/                    the forge plugin - skills, agents, workflows, hooks, bin
plugins/cast/                     the cast plugin - skills, agents, hooks, adapters, bin
.claude/                          this repository's own session config
test.sh                           every check that runs without a Claude Code session
```

A plugin directory holds its own manifest in `.claude-plugin/plugin.json`, its commands as
`skills/<name>/SKILL.md`, its subagents in `agents/`, its hooks in `hooks/hooks.json`, its wrapper
commands in `bin/` and its code in `scripts/`.

## Requirements

- Node on `PATH`.
- Claude Code, recent enough for the features each plugin uses - forge names its own floor and the
  dynamic-workflows setting `/forge:work` needs in `plugins/forge/README.md:52-60`.

## Development

This repository is developed with the plugins it ships. `.claude/skills`, `.claude/agents`,
`.claude/workflows` and `.claude/rules/cast.md` symlink into `plugins/`, so an edit to the source
is live in the session - never edit through the symlink path. Used this way the components lose
their prefix: `/issue`, `/work`, `/map`, `implementer`.

Work is captured as an issue and executed, not written by hand:

```
/issue                 interview, then write the issue with its acceptance criteria
/work <issue-id>       implement and review it until the verdict converges
```

Issues live on GitHub; how they are read and written is `.claude/skills/issue-backend/SKILL.md`.
`.forge/` is local state and mostly gitignored.

Project knowledge is one topic per file under `.claude/rules/`, and what is true of a single
directory lives in `.claude/rules/areas/<area>.md`, loaded only when a file it matches is read.

## Checks

```
forge-test
```

It exits `0` with one line, `<n>/<n> tests succeeded`, or `1` with every failing suite and its
detail. It runs `test.sh`, which needs no Claude Code session and can be run directly:

```
./test.sh
```

## License

MIT - see `LICENSE`.
