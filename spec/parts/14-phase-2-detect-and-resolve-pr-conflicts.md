## 12. Phase 2: detect and resolve PR conflicts

### 12.1 Discovery

List open PRs and determine mergeability.

Schedule a resolution job when all are true:

- PR is open,
- PR base is `main`,
- PR is conflicting with `main`,
- no active PR conflict job exists for that PR.

### 12.2 Worker flow

`worker-resolve-pr.sh <pr_number>`

1. fetch PR metadata,
2. create worktree from PR head,
3. fetch latest `origin/main`,
4. attempt rebase or merge,
5. if conflicts appear:
   - collect conflict files,
   - invoke Codex to resolve only those conflicts,
6. rerun integration command,
7. run validation commands,
8. commit resolved changes,
9. push to the PR branch,
10. optionally post PR summary comment,
11. cleanup.

### 12.3 Constraints

The Codex prompt must instruct:

- resolve merge conflicts only,
- preserve PR intent,
- avoid unrelated refactors,
- avoid formatting unrelated files,
- run minimal validation.

### 12.4 Failure handling

On failure:

- log failure,
- optionally comment on the PR,
- retain the worktree only if configured,
- keep the supervisor alive.

---

