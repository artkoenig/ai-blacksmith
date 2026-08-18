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
