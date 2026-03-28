## 4. Repository layout

Recommended layout:

```text
repo/
  .grkr/
    config.sh
    state/
      last_comment_scan_at
      processed_comments.json
      active_jobs.json
      project_cache.json
      pr_cache.json
    locks/
      main.lock
      comments.lock
      issues.lock
      prs.lock
      pr-456.lock
      issue-123.lock
      comment-789.lock
    logs/
      main.log
      loop.log
      jobs/
        pr-456.log
        issue-123.log
        comment-789.log
    worktrees/
      pr-456/
      issue-123/
      comment-789/
    tasks/
      issue-123-add-search-index/
        meta.env
        issue-context.json
        progress.json
        research.md
        plan.md
        refusal.md
        implementation.log
        test.md
        codex/
          research.prompt.md
          plan.prompt.md
          implement.prompt.md
          refuse.prompt.md
          test.prompt.md
```

---

