# Developing forge

The plugin is `plugins/forge/`. This repository holds it; it does not use it. Editing the files
needs nothing loaded, and the checks below run without a Claude Code session.

## Checks

```bash
claude plugin validate ./plugins/forge --strict
node --check plugins/forge/workflows/work.js
```

Hook scripts read a hook payload on stdin and print a decision or nothing:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  | CLAUDE_PROJECT_DIR=/path/to/a/forge/project node plugins/forge/scripts/guard-bash.js
```

They are gated on `.forge/config.json`, so point `CLAUDE_PROJECT_DIR` at a directory that has one.

The wrappers need the same:

```bash
cd /path/to/a/forge/project && forge-test --failing
```

## Testing the workflow without spending a token

`work.js` is plain JavaScript with `agent`, `phase`, `log` and `parallel` as globals. Read the file,
replace `export const meta` with `const meta`, and run the body with your own stubs:

```js
new Function('agent', 'phase', 'log', 'parallel', 'args', `return (async () => {${src}})()`)
```

Have the stub `agent` return a canned object per label and assert the labels it was called with.
That covers wave order, stall detection, skipped dependents, merge conflicts and blocked
increments - the whole control flow, with no model involved.

## Testing it for real

Install it, in a throwaway project, not here:

```bash
/plugin marketplace add /path/to/this/repo
/plugin install forge@artkoenig-marketplace
/forge:bootstrap
```

`/reload-plugins` picks up changes to `agents/`, `hooks/` and `.mcp.json` mid-session. `SKILL.md`
text is picked up on its own. Output styles are part of the system prompt and need a new session.

## Still unverified

Neither has been observed in a real session:

- Whether `agentType: 'forge:implementer'` resolves a plugin-scoped agent inside a workflow. If it
  does not, the fallback is `general-purpose` with the agent body preloaded through `skills`.
- Whether plugin hooks fire inside workflow-spawned agents. The docs say hooks run inside subagents.
  If they do not fire here, the wrappers alone carry the token budget.
