# Developing forge in this repo

The plugin lives in `plugins/forge/`. `.claude/` symlinks its components into project scope, so a
session started at the repo root loads them from the working tree. Edit the file under
`plugins/forge/`; the symlink points at it.

```
.claude/agents/*.md          -> plugins/forge/agents/*.md
.claude/skills/*             -> plugins/forge/skills/*
.claude/workflows/work.js    -> plugins/forge/workflows/work.js
.claude/output-styles/*      -> plugins/forge/output-styles/*
.claude/settings.json         registers the hooks by path
```

## What updates without `/reload-plugins`

| Component | Live? | Why |
| --- | --- | --- |
| `skills/*/SKILL.md` | yes | Claude Code watches `.claude/skills/` and picks up `SKILL.md` text in the session ([docs](https://code.claude.com/docs/en/skills#live-change-detection)) |
| `agents/*.md` | yes, within seconds | Claude Code watches `.claude/agents/`; the next delegation uses the new definition ([docs](https://code.claude.com/docs/en/sub-agents)) |
| `scripts/*.js` | yes | Hook scripts are read at execution. Only their registration is loaded once |
| `workflows/work.js` | expected | The script is read when the workflow runs. Undocumented - verify before relying on it |
| Hook registration in `.claude/settings.json` | expected | Claude Code fires `ConfigChange` for settings files. Undocumented whether hooks re-register |
| `output-styles/*` | no | Output style is part of the system prompt, read once at session start. `/clear` |
| Anything under an **installed** copy of the plugin | no | `/reload-plugins`, and even that skips output styles and monitors |

Three cases still need a restart, from the subagent docs: a directory that did not exist when the
session started, agents under `--add-dir`, and sessions started with `--disable-slash-commands`.

## Names differ from an installed plugin

Loaded this way the components are project-scope, so they lose the `forge:` prefix:

| Installed | In this repo |
| --- | --- |
| `/forge:issue` | `/issue` |
| `/forge:work` | `/work` |
| `forge:implementer` | `implementer` |

Two consequences:

- Run the workflow with `agentPrefix: ''` so it dispatches the unprefixed agents:
  `/work {"issue": "1", "agentPrefix": ""}`. Installed, the default `forge:` is correct.
- The agents list both `forge:agent-protocol` and `agent-protocol` in `skills:`. A missing one is
  skipped with a warning, so the preload works either way.

`${CLAUDE_PLUGIN_ROOT}` does not substitute in project-scope skills, so `/bootstrap` and
`/new-agent` cannot reach `plugins/forge/templates/` here. Test those two from an installed copy.

## Testing without a session

```bash
claude plugin validate ./plugins/forge --strict
```

The hook scripts read a hook payload on stdin and print a decision or nothing:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
  | CLAUDE_PROJECT_DIR=/path/to/a/forge/project node plugins/forge/scripts/guard-bash.js
```

The workflow's control flow runs against stubbed agents: load `plugins/forge/workflows/work.js`,
replace `export const meta` with `const meta`, and call it with your own `agent`, `phase`, `log`,
`parallel` and `args`. That covers the wave order, stall detection, skipped dependents and merge
conflicts without spending a token.
