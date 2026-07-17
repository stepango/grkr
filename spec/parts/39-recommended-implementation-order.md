## 31. Recommended implementation order

Status snapshot (Gleam v2 product tip **`f6b34d4`** post PR #133 Linear fifth/final thin `process_linear_issue` sequencer — bootstrap + decision/implement stages → `bin/lib/linear_issue_stages.sh`, `linear_issue.sh` 386→329 / stages 599→725 (t_d9eb82bb); lineage fourth extract **`48aa21b`** / PR #131 + docs tip-sync #132 @ **`3e7cbc5`**; third extract **`ce34b29`** / PR #129 + docs tip-sync #130 @ **`b97fecc`**; second extract **`8ae5250`** / PR #127 + docs tip-sync #128 @ **`1ac9be2`**; first extract **`7721b61`** / PR #125 + docs tip-sync #126 @ **`57eef93`**; docs tip lineage **`729abd0`** post PR #124 tip-sync after design **`ad3e9a4`** / PR #123 Linear thinning plan; GitHub process_issue product tip **`a3d9702`** post PR #121 thin `process_issue` orchestrator → `bin/lib/github_issue.sh` after completion PR #119 @ **def63d8** + research/plan PR #117 @ **53592d4** + publish helpers PR #115 @ **6e0f1d3** + test checkpoint PR #112 @ **c438409**, `bin/grkr` 875→738→639→545→527→435; docs tip-sync #122 @ **bdf396b**; docs tip-sync #120 @ **321aa11**; docs tip-sync #118 @ **bf530e5**; docs tip-sync #116 @ **2ac57fb**; docs tip-sync #113 @ **219fde5**; STRICT PR #110 @ **82f3644**; nits PR #107 @ **8d4b674**; land PR #104 @ **e28d0c0**; FFI variables PR #106 @ **36f8f03**; publish+complete dry-run @ **bd523a6** / PR #100; docs tip-sync #111 @ **f07d578**; GitHub-default refusal-aware pipeline; historical counts e.g. **298** pre-MVP / **300** on Linear MVP tip / **304** on refuse tip / **305** on test-stage tip / **316** on live-mutate nits tip):

- Items **1 through 5** were the historical baseline (doctor, supervisor shell loop, sync-main, picker, research/plan checkpoints).
- Items **6 through 12** are **implemented** in Gleam v2 with thin `bin/` delegates; see primary wiring below.
- **Still forward-looking (not blocking GitHub core):** Linear refuse dry-run landed @ **8aba009** (t_503ca0f3 + t_e47417cb / PR #95); implement dry-run @ **d1c1240** (PR #97); test dry-run @ **bfee58c** (PR #98: worktree verify + test.md + planned "In Review" mutations); **publish+complete dry-run landed** @ **bd523a6** (PR #100); **guarded live `GRKR_LINEAR_MUTATE=1` apply landed** @ **e28d0c0** (PR #104) + nits **8d4b674** (PR #107) + optional STRICT **82f3644** (PR #110; default OFF / dry-run; STRICT=1 hard-fails non-refuse apply; refuse.* always soft; stricter parse, soft skipped-no-token, stage-scoped keys); **GitHub process_issue product tip** **a3d9702** (PR #121 thin process_issue orchestrator after **def63d8** / PR #119 completion + **53592d4** / PR #117 research/plan + **6e0f1d3** / PR #115 publish helpers + **c438409** / PR #112 test checkpoint; `bin/grkr` 527→435; no further GitHub shell thinning in this lineage); **Linear thinning design tip** **ad3e9a4** (PR #123); **Linear first extract product tip** **7721b61** (PR #125 / t_9c0c6ab9) + docs tip-sync #126 @ **57eef93**; **Linear second extract product tip** **8ae5250** (PR #127 / t_8ca53b63) + docs tip-sync #128 @ **1ac9be2**; **Linear third extract product tip** **ce34b29** (PR #129 / t_7d3260b2) + docs tip-sync #130 @ **b97fecc**; **Linear fourth extract product tip** **48aa21b** (PR #131 / t_81b53e16) + docs tip-sync #132 @ **3e7cbc5**; **Linear fifth/final thin sequencer product tip** **f6b34d4** (PR #133 / t_d9eb82bb: thin `process_linear_issue` sequencer, 386→329 / stages 599→725; Linear shell thinning complete); `GRKR_ISSUE_PROVIDER=linear` pick+schedule+spawn already lands (t_51747d23 @ ce61881); GitHub remains default; ongoing PR / e2e process polish.

| # | Item | Status | Primary code / wiring |
|---|------|--------|------------------------|
| 6 | implement-or-refuse decision gate | **done** | `workflow/decision_gate.gleam` + `bin/grkr` post-codex path (spec/22) |
| 7 | refusal worker + Backlog transition | **done** | `refusal/*`, `bin/worker-refuse-issue.sh` (spec/23) |
| 8 | implementation stage | **done** | `workflow/implement_stage.gleam` + thin `grkr-issue-workflow.sh` / `bin/grkr` (spec/25, #17) |
| 9 | test stage + completion flow | **done** | `workflow/test_stage.gleam` + completion-marker delegate (spec/26, #18, spec/17) |
| 10 | comment scan + @:robot: commands | **done** | supervisor `scan_comment_commands` + `workflow/handle_comment` + thin `worker-handle-comment.sh` (spec/15) |
| 11 | PR conflict resolution | **done** | `resolve_pr/main` + `bin/worker-resolve-pr.sh`; detection in supervisor phases |
| 12 | cleanup, retry, stale-job recovery | **done** | supervisor cleanup/reap phases, `worktree_cleanup`, `recovery` + active_jobs TTL per `.grkr/supervisor-cleanup-policy.md` §6 (spec/36) |

Ordered build sequence (reference; items 1–12 covered in v2):

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

Spec refresh: kanban **t_21c1cbb1** aligned this snapshot with [docs/gleam-migration.md](../../docs/gleam-migration.md) (items 6–12 **done** table).

---