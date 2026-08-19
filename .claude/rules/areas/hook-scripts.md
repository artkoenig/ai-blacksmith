---
paths:
  - "plugins/forge/scripts/**"
---

# Hook scripts

- `lib.js` holds `readInput`, `projectRoot`, `config`, `emit`. Import it; never parse stdin twice.
- A hook never blocks and never throws. Wrap the work in `try`, end with `emit(null)`.
- `emit(null)` is "no decision". A decision is a `hookSpecificOutput` object with
  `hookEventName` and `permissionDecision`.
- Registration is double: `plugins/forge/hooks/hooks.json` for an installed copy, and
  `.claude/settings.json` by path for this repository. Both, or it does not fire here.
- Scripts are read at execution, so an edit is live. A new script needs both registrations first.
- Exercise one without a session: `echo '<json>' | node plugins/forge/scripts/<name>.js`.
- `test.sh` asserts every script is executable and passes `node --check`. `chmod +x` a new one.
- `guard-checkout.js` binds to `input.agent_type`; anything but `forge:reviewer` passes.
- A change to the hook registration in `.claude/settings.json` is expected to apply without a
  restart - `ConfigChange` fires for settings files - but that is undocumented.

## Where an agent's transcript lives

Verified on 2.1.234, by running an agent: `SubagentStart` and `SubagentStop` both fire for
`Task`-spawned agents with hooks registered in project settings, and the path a `SubagentStop` hook
is handed is the *session's* transcript, not the agent's. The agent's own file is
`<project>/<session-id>/subagents/agent-<agent-id>.jsonl`, and every entry in it carries `agentId`.

`subagent-metrics.js` derives that path and refuses to measure anything it cannot attribute by
`agentId`: measuring the file it was handed would report the session's tokens and tool calls under
the agent's name. A missing number is the expected failure; a wrong one is not. The estimate from
`SubagentStart` reads files, not the transcript, so it holds either way.

## The staleness warning

`session-start.js` warns a cloud session whose plugin checkout is behind the marketplace tip. It
runs only when `CLAUDE_CODE_REMOTE=true`, reads the installed SHA and the marketplace name out of
the `CLAUDE_PLUGIN_ROOT` path (`.../plugins/repos/<marketplace>/<sha>/plugins/forge`) and asks the
tip from the marketplace clone's own `origin`, so a fork checks against the fork. No answer means no
warning. The `git ls-remote` is capped at 10s, which is why the hook's timeout is 20.
