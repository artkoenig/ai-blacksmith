---
paths:
  - "plugins/forge/output-styles/**"
---

# Output styles

- An output style is part of the system prompt, so an edit is **not** live. `/clear` to pick it up.
- `.claude/settings.json` selects one by its `name:`, not by filename.
- The style governs the session's prose; an agent's answering rules live in its own page and in
  `agent-protocol`. Do not restate one in the other.
