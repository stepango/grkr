## 31. Recommended implementation order

Status snapshot (Gleam v2 product tip **`0d13a98`** post PR #154 supervisor phases LOC hygiene (phases.gleam 688→117 thin dispatcher + 7 concern modules; zero behavior change; t_94976f9c); lineage docs tip-sync #153 @ **`4613b02`** after github_issue completion polish **`29c7a4b`** / PR #152 + docs tip-sync #151 @ **`c918cde`** after coding-agent matrix **`1edf636`** / PR #150 + swappable coding agent **`d55dd73`** / PR #149 + docs tip-sync #148 @ **`745ca83`** after github_issue PR body helpers **`1216e94`** / PR #147 (ensure_pr_body_limit + extract_codex_pr_body → Gleam; github_issue.sh 545→543 / templates 176→221; t_e06571e3) + design **`15a5050`** / PR #146 + docs tip-sync #145 @ **`9a1b8f6`** after shared fifth extract **`c801967`** / PR #144 + fourth extract **`f6fb872`** / PR #142 + docs tip-sync #143 @ **`3b0b2df`** + third extract **`325ee9a`** / PR #140 + docs tip-sync #141 @ **`36de1a1`** + second extract **`593e18b`** / PR #138 + docs tip-sync #139 @ **`ce37e6a`** + first extract **`d04f5e9`** / PR #136 + docs tip-sync #137 @ **`5e53aaf`** + design **`d90fbaf`** / PR #135 + docs tip-sync #134 @ **`5418159`** after Linear fifth/final thin sequencer **`f6b34d4`** / PR #133 + docs tip-sync #132 @ **`3e7cbc5`** after fourth extract **`48aa21b`** / PR #131; third extract **`ce34b29`** / PR #129 + docs tip-sync #130 @ **`b97fecc`**; second extract **`8ae5250`** / PR #127 + docs tip-sync #128 @ **`1ac9be2`**; first extract **`7721b61`** / PR #125 + docs tip-sync #126 @ **`57eef93`**; docs tip lineage **`729abd0`** post PR #124 tip-sync after design **`ad3e9a4`** / PR #123 Linear thinning plan; GitHub process_issue product tip **`a3d9702`** post PR #121 thin `process_issue` orchestrator → `bin/lib/github_issue.sh` after completion PR #119 @ **def63d8** + research/plan PR #117 @ **53592d4** + publish helpers PR #115 @ **6e0f1d3** + test checkpoint PR #112 @ **c438409**, `bin/grkr` 875→738→639→545→527→435→339→279→260→233→198; docs tip-sync #122 @ **bdf396b**; docs tip-sync #120 @ **321aa11**; docs tip-sync #118 @ **bf530e5**; docs tip-sync #116 @ **2ac57fb**; docs tip-sync #113 @ **219fde5**; STRICT PR #110 @ **82f3644**; nits PR #107 @ **8d4b674**; land PR #104 @ **e28d0c0**; FFI variables PR #106 @ **36f8f03**; publish+complete dry-run @ **bd523a6** / PR #100; docs tip-sync #111 @ **f07d578**; GitHub-default refusal-aware pipeline; historical counts e.g. **298** pre-MVP / **300** on Linear MVP tip / **304** on refuse tip / **305** on test-stage tip / **316** on live-mutate nits tip):

- Items **1 through 5** were the historical baseline (doctor, supervisor shell loop, sync-main, picker, research/plan checkpoints).
- Items **6 through 12** are **implemented** in Gleam v2 with thin `bin/` delegates; see primary wiring below.
- **Still forward-looking (not blocking GitHub core):** Linear refuse dry-run landed @ **8aba009** (t_503ca0f3 + t_e47417cb / PR #95); implement dry-run @ **d1c1240** (PR #97); test dry-run @ **bfee58c** (PR #98: worktree verify + test.md + planned "In Review" mutations); **publish+complete dry-run landed** @ **bd523a6** (PR #100); **guarded live `GRKR_LINEAR_MUTATE=1` apply landed** @ **e28d0c0** (PR #104) + nits **8d4b674** (PR #107) + optional STRICT **82f3644** (PR #110; default OFF / dry-run; STRICT=1 hard-fails non-refuse apply; refuse.* always soft; stricter parse, soft skipped-no-token, stage-scoped keys); **GitHub process_issue product tip** **a3d9702** (PR #121 thin process_issue orchestrator after **def63d8** / PR #119 completion + **53592d4** / PR #117 research/plan + **6e0f1d3** / PR #115 publish helpers + **c438409** / PR #112 test checkpoint; `bin/grkr` 527→435; no further GitHub shell thinning in this lineage); **Linear thinning design tip** **ad3e9a4** (PR #123); **Linear first extract product tip** **7721b61** (PR #125 / t_9c0c6ab9) + docs tip-sync #126 @ **57eef93**; **Linear second extract product tip** **8ae5250** (PR #127 / t_8ca53b63) + docs tip-sync #128 @ **1ac9be2**; **Linear third extract product tip** **ce34b29** (PR #129 / t_7d3260b2) + docs tip-sync #130 @ **b97fecc**; **Linear fourth extract product tip** **48aa21b** (PR #131 / t_81b53e16) + docs tip-sync #132 @ **3e7cbc5**; **Linear fifth/final thin sequencer product tip** **f6b34d4** (PR #133 / t_d9eb82bb: thin `process_linear_issue` sequencer, 386→329 / stages 599→725; Linear shell thinning complete) + docs tip-sync #134 @ **5418159**; **shared helpers design tip** **d90fbaf** (PR #135); **shared helpers first extract product tip** **d04f5e9** (PR #136 / t_d9c18700: test-write cluster → `bin/lib/issue_shared.sh`, `bin/grkr` 435→339 / issue_shared 110) + docs tip-sync #137 @ **5e53aaf**; **shared helpers second extract product tip** **593e18b** (PR #138 / t_9e60aed0: line-limit + ensure_publishable → `bin/lib/issue_shared.sh`, `bin/grkr` 339→279 / issue_shared 110→178) + docs tip-sync #139 @ **ce37e6a**; **shared helpers third extract product tip** **325ee9a** (PR #140 / t_2091085e: run_codex_prompt → `bin/lib/issue_shared.sh`, `bin/grkr` 279→260 / issue_shared 178→198) + docs tip-sync #141 @ **36de1a1**; **shared helpers fourth extract product tip** **f6fb872** (PR #142 / t_bc6ebfda: run_progress_cli + checkpoint_marker → `bin/lib/issue_shared.sh`, `bin/grkr` 260→233 / issue_shared 198→228) + docs tip-sync #143 @ **3b0b2df**; **shared helpers fifth extract product tip** **c801967** (PR #144 / t_2847ff4d: attach_issue_logs → `bin/lib/issue_shared.sh`, `bin/grkr` 233→198 / issue_shared 228→249) + docs tip-sync #145 @ **9a1b8f6**; **github_issue thinning design tip** **15a5050** (PR #146 / t_0f32e023); **github_issue PR body helpers product tip** **1216e94** (PR #147 / t_e06571e3: ensure_pr_body_limit + extract_codex_pr_body → Gleam progress/templates + cli, `github_issue.sh` 545→543 / templates 176→221) + docs tip-sync #148 @ **745ca83**; **swappable coding agent product tip** **d55dd73** (PR #149); **coding-agent matrix + quality eval harness product tip** **1edf636** (PR #150) + docs tip-sync #151 @ **c918cde**; **github_issue completion summary polish product tip** **29c7a4b** (PR #152 / t_dec62328: render_github_completion_summary → Gleam + thin post_completion_comment; github_issue.sh 543→542 / templates 221→238) + docs tip-sync #153 @ **4613b02**; **supervisor phases LOC hygiene product tip** **0d13a98** (PR #154 / t_94976f9c: phases.gleam 688→117 + 7 concern modules); `GRKR_ISSUE_PROVIDER=linear` pick+schedule+spawn already lands (t_51747d23 @ ce61881); GitHub remains default; ongoing PR / e2e process polish.

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