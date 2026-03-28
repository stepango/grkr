## 10. Worktree model

### 10.1 Naming

Worktree path examples:

- `.grkr/worktrees/pr-456`
- `.grkr/worktrees/comment-789`
- `.grkr/worktrees/issue-123-add-search-index`

Branches:

- `robot/pr-456-conflict`
- `robot/comment-789`
- `robot/issue-123-add-search-index`

### 10.2 Lifecycle

For each worker:

1. create worktree,
2. configure git author,
3. fetch needed refs,
4. perform work,
5. commit and push if needed,
6. update job state,
7. remove worktree,
8. periodically prune stale worktrees.

### 10.3 Base refs

- PR conflict job base: PR head branch
- PR comment job base: PR head branch
- issue comment job base: latest `main`
- issue execution base: latest `origin/main`
- issue refusal base: latest `origin/main` if repo context is needed, otherwise no worktree required

---

