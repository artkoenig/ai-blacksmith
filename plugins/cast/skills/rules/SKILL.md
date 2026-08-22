---
name: rules
description: Try a layer rule against the module graph before it is written down - how many imports it would flag today, and which. Use when someone proposes a dependency the project should forbid, or asks what a rule would cost.
argument-hint: "[rule json, e.g. {\"name\":\"ui-off-data\",\"severity\":\"error\",\"from\":\"ui\",\"to\":\"data\",\"kinds\":[\"value\"]}]"
allowed-tools: Bash, Read
---

# A rule, before it is written down

The argument is one rule object - the same shape a `forbidden` entry in `<root>/.cast/rules.json`
has. Without one, ask for the rule; never invent a `from` and `to` from the last file read.

!`CAST="$(command -v cast || echo "${CLAUDE_PLUGIN_ROOT:-plugins/cast}/bin/cast")"; "$CAST" scan >/dev/null && "$CAST" rules preview "$ARGUMENTS"`

The preview reports and exits 0 even where it flags everything - a rule that is expensive today is
not an error. Exit 2 is a rule this evaluator cannot read at all: fix the object and run it again.

- The count is module edges, not modules. One module with three forbidden imports is three imports
  to move, and the modules are named beside the number.
- The project's `allowed` exceptions are already applied, so the count is what `cast check` would
  add if this rule were adopted today.
- `not evaluated` names an attribute this evaluator does not know. Treat that rule as unproven, not
  as passing.

Report the count, the layer edges it falls on, and the sites. Then say what adopting it costs: it
goes into `<root>/.cast/rules.json` as-is, or its current violations go into
`<root>/.cast/baseline.json` and the rule is green from today - `cast baseline --update` can only
ever shrink that file.
