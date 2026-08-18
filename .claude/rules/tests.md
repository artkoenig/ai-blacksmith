# tests

A test earns its place by its break.

- A criterion counts as tested only when at least one of its tests fails if the behaviour it
  asks for is broken or removed.
- Name the break before writing the case: `<criterion> - <input and state> -> <expected result>
  - break: <the production change that would make it fail>`.
- A case whose break you cannot name catches nothing. Drop it or rewrite it.
- Prove the break where it is cheap: remove the line the case exists for, see the suite go red,
  put it back.
- Where a criterion gets no such case, say so and why. The omission is a decision, not a gap.
