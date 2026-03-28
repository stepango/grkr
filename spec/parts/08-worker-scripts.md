## 6.2 Worker scripts

Recommended scripts:

```text
doctor.sh
worker-sync-main.sh
worker-scan-pr-conflicts.sh
worker-resolve-pr.sh
worker-scan-comments.sh
worker-handle-comment.sh
worker-pick-issue.sh
worker-exec-issue.sh
worker-refuse-issue.sh

lib/common.sh
lib/log.sh
lib/lock.sh
lib/state.sh
lib/github.sh
lib/git.sh
lib/worktree.sh
lib/codex.sh
lib/project.sh
```

### Responsibilities

- `doctor.sh`: validate tools, auth, repo, config
- `worker-sync-main.sh`: sync main checkout
- `worker-scan-pr-conflicts.sh`: discover conflicting PRs and schedule jobs
- `worker-resolve-pr.sh`: resolve conflicts in a dedicated worktree
- `worker-scan-comments.sh`: discover new `@:robot:` comments
- `worker-handle-comment.sh`: process one comment in a dedicated worktree
- `worker-pick-issue.sh`: find the highest-priority eligible Todo issue
- `worker-exec-issue.sh`: run the issue workflow
- `worker-refuse-issue.sh`: generate refusal reasoning, post comment, and move item to Backlog

---

