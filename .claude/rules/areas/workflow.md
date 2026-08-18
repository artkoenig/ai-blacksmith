---
paths:
  - "plugins/forge/workflows/**"
---

# The run loop

- `work.js` is the only workflow. It runs one wave per dependency level: implement, review, repair,
  merge.
- Every intermediate result stays in a script variable. Nothing an agent returns is echoed into the
  orchestrator context.
- `agentPrefix` resolves the agent names. Installed it is `forge:`; in this repository it is `""`.
- Outcomes the control flow must keep producing: `merged`, `stalled`, `skipped` for a dependent of
  a stall, `conflicted` for a merge conflict, `error` for a missing issue id.
- The control-flow suite in `test.sh` drives the loop against stubbed agents. Any new outcome needs
  a case there; the stubs, not a real run, are what proves it.
- The script is read when the workflow runs, so an edit is live.
