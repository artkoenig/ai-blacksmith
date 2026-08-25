# ai-blacksmith

Two Claude Code plugins for the part of the job an agent usually leaves to you: deciding what
"done" means, and proving it got there.

```
/plugin marketplace add artkoenig/ai-blacksmith
/plugin install forge@artkoenig-marketplace
/plugin install cast@artkoenig-marketplace
```

**forge** turns a request into an issue with verifiable acceptance criteria, then runs it -
implement, review, repair - until a reviewer that reads the issue itself passes it and merges.
**cast** reads your module graph, so the restructuring is judged on a simulation before a file is
touched.

Both are MIT, both are Node and shell, neither calls a service of its own.

## forge - the issue is the unit of work, not the prompt

A prompt is gone the moment the session ends, and nothing can be graded against it. So `/forge:issue`
interviews you and writes one artefact instead: a goal, numbered acceptance criteria, what is out of
scope - and against each criterion the command that decides it.

```
## Acceptance criteria
- AC1 a check that was already red at the base is reported as preexisting, never as a finding
  | verify: forge-test --run reviewer-base
- AC2 a verdict that repeats the previous round's failed set ends the loop | verify: forge-test --run stall
```

Before the first question reaches you, it dispatches a read-only search for what the codebase
already answers, so the interview asks only what the code cannot
(`plugins/forge/skills/issue/SKILL.md:10-32`). Every verify command is scoped and run while the issue
is written - a criterion whose command can go red for an unrelated reason is a false failure nobody
caused (`plugins/forge/skills/issue/SKILL.md:77-86`).

Then it stops. Filing an issue is not asking for it to be built; the run costs agent dispatches, and
when to pay them is your call (`plugins/forge/skills/issue/SKILL.md:122-124`).

## /forge:work - a loop that converges or says it did not

```
/forge:work 42
```

An implementer commits, a reviewer judges the accumulated diff against the criteria, and a repair
round fixes only the criteria that failed. Four properties are what make that more than a retry:

- **The reviewer reads the issue itself.** Nothing the implementer wrote about its own work reaches
  it - an account of the change would be what it graded (`plugins/forge/workflows/work.js:16-17`).
- **It stops when it stalls.** A round that fails the same set as the round before it ends the loop
  and says so, with an eight-round cap behind it for a verdict that oscillates
  (`plugins/forge/workflows/work.js:12-14`, `:284-288`).
- **A red check that was already red is not your bug.** The reviewer reproduces it at the base in a
  throwaway worktree before filing it as a finding; a preexisting failure filed as one is turned
  back into a failed criterion of its own (`plugins/forge/workflows/work.js:188`, `:247-263`).
- **Increments run in parallel, in real worktrees.** Where the issue was cut, each increment gets
  `.claude/worktrees/forge-<issue>-<id>` and its own branch, so concurrent implementers never see
  each other's tree. The reviewer that passes an increment lands it.

The run prints every round and every verdict as it happens, and asks you nothing while it is going -
so it is a thing you start and read, not a thing you babysit.

## cast - the architecture read from the graph, not from memory

`cast scan` writes the module graph outside the checkout; everything else reads it back. Run against
this repository's own forge plugin:

```
$ cast report --root plugins/forge
modules 8
edges 20 (value 20)
  module 6, external 14, unresolved 0, opaque 0
layers 2
  scripts 7
  workflows 1
unassigned 0
unresolved 0
opaque 0
cycles 0
```

Every edge carries the file and line of the import behind it, so `cast edges --from ui --to logic`
lists the actual import statements behind a layer edge you want gone.

- **A rule is the dependency you do not allow**, in `.cast/rules.json`, between two layers or two
  files, and `kinds` keeps an `import type` from tripping a value rule.
- **A baseline is a ratchet.** `.cast/baseline.json` holds the violations you inherited, so a rule
  can be turned on before the code obeys it - and `cast baseline --update` refuses, exit 1, to write
  a baseline larger than the one it replaces. The debt can only shrink.
- **A refactoring is judged before it is executed.** Write it as `move`, `merge`, `invert`, `split`
  operations; `cast plan simulate` applies them to a copy of the graph and reports the cycles, the
  layer metrics and the rule violations before and after. It writes no source file and no graph
  file.
- **The result is a page, not a wall of text.** `cast render --html` opens any node to any depth and
  names the rule behind every breaking edge; `cast render --mermaid` is the version that goes into
  an issue.

The graph is derived state, so nothing lands in your tree and there is nothing to gitignore. A
language arrives as an adapter file - patterns, comment syntax, a `resolve` function - not as a
change to the engine.

## Together

`/map` says the `ui -> data` edge exists and names the six imports behind it. `/plan` simulates the
inversion and reports what it does to the cycles. `/forge:issue` turns the accepted plan into
criteria with verify commands, `/forge:work` executes it and merges when the reviewer passes it. The
architecture question and the diff that answers it are the same workflow.

## The token budget is measured, not asserted

Every agent dispatch re-pays a system prompt, the CLAUDE.md hierarchy and the project rules. forge
treats that as the unit of cost and pushes back on it in the places that pay off, each owned by one
file (`plugins/forge/README.md:27-40`):

| Lever | What it saves |
| --- | --- |
| Area notes under `.claude/rules/areas/` | Directory knowledge loads only when a file it matches is read |
| The loop's intermediate results, held in workflow variables | Verdicts and diffs never enter a session context |
| Wrapper commands in `bin/` | One line of output instead of a second look at raw runner noise |
| A `PreToolUse` hook rewriting a raw check to its wrapper | The expensive form is not run twice |
| A `PostToolUse` hook withholding oversized Bash output | A 200 KB command result does not land in context |

`/forge:context` breaks a run's start down by source, `/forge:stats` reads tool calls and tokens per
run out of `.forge/metrics.jsonl`. Both read measurements, not estimates - if a change to your rules
makes every agent more expensive, it is visible the next run.

## What it is honest about

- A run of `/forge:work` cannot ask you anything. Everything the work needs is settled in the issue,
  or the implementer reports itself blocked.
- A cut into increments halves nothing - it adds a dispatch set. forge cuts only where the parts are
  genuinely independent, one diff would be too large to review, or one part must land first
  (`plugins/forge/skills/issue/SKILL.md:103-116`).
- cast's javascript adapter matches regexes, not an AST - deliberately, and with one visible
  consequence it documents: an inline `import { type X }` is classified `value`
  (`plugins/cast/README.md:291-297`).

## Install and requirements

Install at user scope - a project-scope plugin loads only after the workspace trust dialog.

- Node on `PATH`.
- For forge: Claude Code v2.1.154 or later with dynamic workflows available on your plan - without
  them there is no `/forge:work`. `/forge:context` wants v2.1.234 or later for its `SubagentStart`
  hook (`plugins/forge/README.md:52-60`).
- Then, in the target repository: `/forge:bootstrap`. It detects your check commands and your issue
  storage, writes the adapter and the rules, and says what breaks.

cast needs no setup: without a `.cast/layers.json` the first directory level is the layer, which is
enough to open a view on any project.

Full command reference: `plugins/forge/README.md` and `plugins/cast/README.md`. Each behaviour is
defined in its own file, and only there - a copy in a README drifts.

## Working on this repository

The plugins are developed with the plugins. `.claude/skills`, `.claude/agents`, `.claude/workflows`
and `.claude/rules/cast.md` symlink into `plugins/`, so an edit to the source is live in the session
- never edit through the symlink path. Used this way the components lose their prefix: `/issue`,
`/work`, `/map`, `implementer`.

```
.claude-plugin/marketplace.json   the marketplace entry both plugins install from
plugins/forge/                    skills, agents, workflows, hooks, bin, scripts
plugins/cast/                     skills, agents, hooks, adapters, bin, scripts
test.sh                           every check that runs without a Claude Code session
```

Checks run through `forge-test`, which exits `0` with one line, `<n>/<n> tests succeeded`, or `1`
with every failing suite and its detail. `./test.sh` runs the same suites directly. No plugin pins a
version: each is released from the tip of `main`, so the commit is the version (`test.sh:12-14`).

## License

MIT - see `LICENSE`.
