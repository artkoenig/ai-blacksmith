---
paths:
  - ".claude/rules/**"
---

# Rules and area notes

`.claude/rules/` carries this project's own knowledge into an agent. The rules forge itself works
by are not written here: `scripts/session-start.js` injects `plugins/forge/rules/forge.md` as
`additionalContext`, so a plugin update carries them and no second bootstrap is needed. A rule without
front matter loads at every start, for every agent. A rule with a `paths:` glob loads only when a
file it matches is read, so per-directory knowledge costs nothing until someone works there.

Verified on 2.1.234, by writing a rule with a marker string and watching for it:

| Reaching a file by | Loads the note |
| --- | --- |
| `Read` | yes, as a `system-reminder` right after the tool result |
| `Grep` | no |
| `Bash` (`cat`, `sed`, `grep`) | no |

- `Edit` needs a prior `Read`, so a file an agent changes hands it the note before the change.
- For an area only inspected, one narrow `Read` with `offset` and `limit` buys the note for the
  rest of the run. Hence the protocol names `Read` before `sed -n`.
- A note loads once per session. The second read of the same area is silent.
- Rules are resolved when a file is read, not watched: a new note counts on the next read, no
  restart, even as the first file in a directory created mid-session.
- What a note may hold, and its line budget, live in `plugins/forge/skills/insights/SKILL.md`
  alone. Nothing else states them; `test.sh` reads the budget from there.
- Whoever learns something about an area runs the `forge:insights` skill with that directory. It
  writes the note into the checkout the caller works in.
