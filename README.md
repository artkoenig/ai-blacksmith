# ai-blacksmith

Your agent says "done". Nobody checked. **forge** makes an agent write down what done means -
numbered acceptance criteria, each with the command that decides it - and then runs the work until a
second agent, which reads the issue and never the implementer's report, passes it and merges.
**cast** does the same for architecture: it reads your module graph, so a refactoring is judged on a
simulation before a file is touched.

```
/plugin marketplace add artkoenig/ai-blacksmith
/plugin install forge@artkoenig-marketplace
/plugin install cast@artkoenig-marketplace
```

## Why you would try it

- **A verdict, not a summary.** The reviewer grades the diff against the issue's criteria. What the
  implementer says about its own work never reaches it.
- **It admits when it is stuck.** A round that fails the same criteria as the round before ends the
  loop and says so. No twelfth attempt at the same wrong idea.
- **Someone else's red is not your bug.** A failing check is reproduced at the base commit in a
  throwaway worktree before it is filed against your change.
- **Start it and walk away.** `/forge:work 42` implements, reviews, repairs and merges. Independent
  increments run in parallel, each in its own git worktree.
- **You approve the plan, not the diff.** `/forge:issue` interviews you, greps the codebase for what
  it can answer itself, writes the issue - and stops. The run is yours to start.
- **The token bill is measured.** `/forge:context` shows what each agent loads at startup and where
  it came from; `/forge:stats` shows tool calls and tokens per run. Not estimates.
- **Cycles and layer breaks, with the import behind them.** `cast report` names every dependency
  cycle and every unresolved import; `cast edges --from ui --to data` lists the exact lines.
- **Refactor on paper first.** Describe the move as `move` / `merge` / `invert` / `split`;
  `cast plan simulate` reports the cycles, layer metrics and rule violations before and after,
  writing no source file.
- **Architecture debt that can only shrink.** `cast baseline --update` refuses to write a baseline
  holding more violations than the one it replaces.
- **Nothing to clean up.** cast writes the graph outside your checkout - no artefact in the tree, no
  gitignore entry. No service is called by either plugin.

## In 60 seconds

```
$ cast report --root plugins/forge
modules 8
edges 20 (value 20)
  module 6, external 14, unresolved 0, opaque 0
layers 2
  scripts 7
  workflows 1
cycles 0
```

```
/forge:bootstrap          once per repo: finds your test commands and issue storage
/forge:issue              interview -> an issue with criteria and verify commands
/forge:work 42            implement, review, repair, merge - hands off
/map  /plan               the graph, and what a restructuring would do to it
```

## Honestly

- A `/forge:work` run cannot ask you anything. What the work needs is settled in the issue, or the
  implementer stops and reports itself blocked.
- Splitting an issue into increments costs an extra pair of agent dispatches. forge splits only
  where the parts are genuinely independent or one diff would be too large to review.
- cast's javascript adapter matches regexes, not an AST. One visible consequence, documented: an
  inline `import { type X }` is classified as a value import.

## Requirements

Node on `PATH`. For `/forge:work`, Claude Code v2.1.154 or later with dynamic workflows available on
your plan. Install at user scope - a project-scope plugin loads only after the workspace trust
dialog. Then run `/forge:bootstrap` in your repository; it checks the rest and says what breaks.

## More

`plugins/forge/README.md` and `plugins/cast/README.md` are the full references. Each behaviour is
defined in its own file and only there, so nothing here restates it.

Working on this repository: the plugins are developed with the plugins. `.claude/skills`,
`.claude/agents` and `.claude/workflows` symlink into `plugins/` - edit the source, never the
symlink. Checks run through `forge-test`, or `./test.sh` directly. MIT, see `LICENSE`.
