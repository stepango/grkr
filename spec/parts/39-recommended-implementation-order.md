## 31. Recommended implementation order

Status snapshot:

- The current codebase largely covers items 1 through 5.
- Items 6 through 12 remain the forward-looking backlog described by this spec.

1. `doctor.sh`
2. supervisor loop + logging + locks
3. sync-main worker
4. project issue picker
5. issue workflow with research and plan checkpoints
6. implement-or-refuse decision gate
7. refusal worker and Backlog transition
8. implement stage
9. test stage
10. comment scanning + reactions
11. PR conflict resolution
12. cleanup and retry polish

Tracked issues for this implementation order:

1. [#10 - Add doctor.sh validation for tools, auth, repo, and config](https://github.com/stepango/grkr/issues/10)
2. [#11 - Add supervisor loop, logging, and lock orchestration](https://github.com/stepango/grkr/issues/11)
3. [#12 - Add worker-sync-main.sh to fast-forward the supervisor checkout to origin/main](https://github.com/stepango/grkr/issues/12)
4. [#13 - Add worker-pick-issue.sh for project Todo selection and prioritization](https://github.com/stepango/grkr/issues/13)
5. [#14 - Add research and plan checkpoints to the issue workflow](https://github.com/stepango/grkr/issues/14)
6. [#15 - Add implement-or-refuse decision gate for issue execution](https://github.com/stepango/grkr/issues/15)
7. [#16 - Add worker-refuse-issue.sh and Backlog transition handling](https://github.com/stepango/grkr/issues/16)
8. [#17 - Add the implementation stage for issue workflows](https://github.com/stepango/grkr/issues/17)
9. [#18 - Add the test stage and completion flow for issues](https://github.com/stepango/grkr/issues/18)
10. [#19 - Add worker-scan-comments.sh and worker-handle-comment.sh for @:robot: commands](https://github.com/stepango/grkr/issues/19)
11. [#20 - Add worker-resolve-pr.sh for merge-conflict resolution in isolated worktrees](https://github.com/stepango/grkr/issues/20)
12. [#21 - Add cleanup, retry, and stale-job recovery polish](https://github.com/stepango/grkr/issues/21)

This order gets the refusal-aware issue pipeline working early, which is important for safe autonomous operation.

---
