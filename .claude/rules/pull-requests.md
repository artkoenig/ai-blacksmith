# pull requests

A pull request this session opened is this session's to land.

- Subscribe to every PR you open, with `subscribe_pr_activity`. The subscription runs until the
  PR is merged or closed. Never poll with `sleep`; the events wake the session.
- A merge conflict is work now: merge the base branch into the PR head, resolve it, run
  `forge-test`, push. Never rebase, amend or force-push a branch someone else may have checked out.
- Red CI on your own PR is the same: root-cause it, fix, push, repeat until green. Rule out a
  failure the base branch shows too before touching the diff. Never skip or disable a test to
  get there.
- Where a fix is not yours to make, say once what is failing and why. Silence is not an option.
