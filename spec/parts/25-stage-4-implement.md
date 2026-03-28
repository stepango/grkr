## 21. Stage 4: implement

This stage runs only if the decision gate returns `proceed`.

### 21.1 Inputs

- `research.md`
- `plan.md`
- issue context
- repository worktree

### 21.2 Output

Codex modifies files in the issue worktree and implementation logs are stored in:

```text
.grkr/tasks/<slug>/implementation.log
```

### 21.3 Constraints

The implementation prompt must instruct Codex to:

- follow the plan,
- minimize unrelated edits,
- avoid large opportunistic refactors,
- run configured build and test commands,
- stage only relevant files.

### 21.4 Commit strategy

Commit message example:

```text
feat(robot): implement #123 add search index
```

or

```text
fix(robot): implement #123 stabilize cache invalidation
```

### 21.5 Branch strategy

Default behavior:

- push issue branch
- create or update a PR for that branch
- link the issue in the PR body

### 21.6 Escalation from implement to refuse

If implementation begins but the agent discovers issue-quality blockers that should have caused refusal, it may still switch to refusal **before** posting final success.

When that happens:

- preserve `implementation.log`
- generate `refusal.md`
- post refusal comment
- move issue to Backlog
- mark workflow as `refused`

This prevents half-finished silent failures.

---

