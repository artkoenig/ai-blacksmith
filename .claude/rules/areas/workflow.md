---
paths:
  - "plugins/forge/workflows/**"
---

# The run loop

- `work.js` is the only workflow. It runs one wave per dependency level: implement, review, repair.
  The implementer commits every round; the reviewer merges the increment it passes. No step of the
  run does either on its own.
- Every increment lands from its own worktree: rebase onto the issue branch tip, then
  `git update-ref refs/heads/<issue-branch> <new> <tip>`. The compare-and-swap fails when another
  reviewer landed in between, and that reviewer rebases again. Nothing is serialized.
- Two writes into the main checkout at once collide on its one index and one HEAD - `cannot lock
  ref 'HEAD'`, and the loser's half-merge stays in the index. That is why no agent merges there.
- `update-ref` moves a branch that the main checkout has checked out, unlike `git branch -f` or
  `git push .`, both of which refuse. The cost is that the main checkout's files then lag its
  HEAD: the run returns `checkout: 'stale'`, and its caller refreshes with one `git reset --hard`.
- Every intermediate result stays in a script variable. Nothing an agent returns is echoed into the
  orchestrator context.
- `agentPrefix` resolves the agent names. Installed it is `forge:`; in this repository it is `""`.
- Outcomes the control flow must keep producing: `merged`, `stalled`, `skipped` for a dependent of
  a stall, `conflicted` for a merge conflict, `error` for a missing issue id.
- The control-flow suite in `test.sh` drives the loop against stubbed agents. Any new outcome needs
  a case there; the stubs, not a real run, are what proves it.
- The script is read when the workflow runs, so an edit is expected to be live. Undocumented.

Two things about a workflow-spawned agent are unverified, never observed in a real session:
whether `agentType: 'forge:implementer'` resolves a plugin-scoped agent inside a workflow, and
whether plugin hooks fire inside one. Here the unprefixed names and the project settings are used
instead, so both stay open until someone runs an installed copy.
