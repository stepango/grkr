## 22. Stage 5: test

This stage runs only if implementation succeeded.

### 22.1 Inputs

- final implementation worktree
- configured commands

### 22.2 Output

Write:

```text
.grkr/tasks/<slug>/test.md
```

It must include:

- commands run
- pass/fail summary
- output excerpts
- remaining risks
- recommendation: ready or needs follow-up

### 22.3 Issue checkpoint comment

Post `test.md` as issue comment.

### 22.4 Completion actions

On success:

- optionally move project item to `In Progress` or `Done`
- comment final summary
- record branch and PR URL
- mark `progress.json.status = complete`

---

