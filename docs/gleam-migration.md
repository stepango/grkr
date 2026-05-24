# Gleam v2 Migration Status

**Current implementation status (2026-05-24, post t_58ea0e02 scheduler impl + t_767a0b08 test+docs+sync + t_78a7818e worktree prune + t_65d650b7 review (PR #79 supervisor/phases/scheduler) + t_55147911 (docs follow-up) + reviews of PR #79 slices; open PR #79 https://github.com/stepango/grkr/pull/79 ): GitHub-only first.**

The migration uses small kanban-driven slices (decomposition required because large parent cards repeatedly hit 90/90 max_iterations limit during complex impl; see e.g. blocked t_483bf2fb etc.). 

**Key Gleam modules implemented (all <1000 LOC, `gleam build` clean, `gleam test` 228 passed, 0 failures):**

- **github_picker/** (project issue selector for GitHub V2; thin integration + client complete):
  - config.gleam (193 LOC), types.gleam (138), query.gleam (128), decoder.gleam (166), selector.gleam (153), field.gleam (104), priority.gleam (64), main.gleam (161), client.gleam (137)
  - + ffi.gleam (42), cli_ffi.mjs, env.mjs, file.mjs, json_ffi.mjs, gh_exec.mjs (for thin fetch/pagination)
  - Wired via updated bin/worker-pick-issue.sh (40 LOC thin wrapper)

- **refusal/** (refusal assessment + full flow + checkpoints per spec 21/23/27):
  - flow.gleam (352 LOC), assessment.gleam (111), types.gleam (165), config.gleam (57), checkpoint.gleam (186), ffi.gleam (52) + json_ffi.mjs, fs.mjs
  - cli.gleam (129 LOC) for `gleam run -m grkr/refusal/cli`
  - Wired via thin bin/worker-refuse-issue.sh (57 LOC wrapper: doctor+env+`exec gleam run -m grkr/refusal/cli -- "$@"`)

- **supervisor/** (loop orchestration, recovery, locking, state + phases; per design in supervisor-design-final.md; phases extraction + impl complete):
  - main.gleam (56 LOC), phases.gleam (517 LOC), loop.gleam (182 LOC, delegates dispatch + pick to phases), recovery.gleam (214), config.gleam (163), types.gleam (181 + GitHubComment/processed_comments fns), state.gleam (245), lock.gleam (88), ffi.gleam (125), scheduler.gleam (130)
  - + process/exec/file/env/fs mjs
  - Entry point; thin bin/robot-main.sh (57 LOC) delegates to `gleam run -m grkr/supervisor/main`
  - Phases (per 09-contract, 07, 39-order items 10-12): sync_main (delegates worker-sync-main.sh), scan_pr_conflicts (uses resolve_pr_github + active_jobs filter), scan_comment_commands (lock+state read + processed state prep per spec/15), pick_and_schedule (github_picker wired + full scheduler.spawn for record_active_job + detached flock spawn + pid capture + job logs), reap (recovery), cleanup (purge stale locks + wt count stub per 36)

- **Fully or substantially migrated supporting modules:**
  - sync_main/main.gleam (205 LOC) + thin bin/worker-sync-main.sh (18 LOC)
  - resolve_pr/ (main.gleam 426 LOC + git.gleam 240, github.gleam 121, codex.gleam 134, types 47) + thin bin/worker-resolve-pr.sh (43 LOC) — full PR conflict resolution
  - issue_provider/ (Linear experimental: main 236, config(269), selector(150), query(200), decoder(225), credential(182), validation 88, client 65, types 222, ffi 26 etc.)
  - progress/ (cli.gleam 108, main 231, checkpoint_render 103, linear_mutation 174, linear_state 112, checkpoint_id 74, checkpoint_stage 64 etc. — used by grkr CLI and workers for checkpoints + Linear)
  - task_slug/ (core 90 + cli 44)
  - project_status/ (planning 341, extraction 217, resolution 141, types 112, config 101, normalization 46, main 5, cli 278)
  - linear/ (e2e 272 + oauth 353, client 209, config 147, graphql 106, types 75, e2e_main 20)

**Shell / bin/ status (per AGENTS.md: preserve existing shell-script conventions in bin/ and test/; keep changes small/explicit):**
- Thin Gleam delegates: worker-sync-main.sh (18 LOC), worker-resolve-pr.sh (43 LOC), worker-pick-issue.sh (40 LOC), robot-main.sh (57 LOC), worker-refuse-issue.sh (57 LOC)
- Thick (full reimpl pending in follow-up cards): grkr-issue-workflow.sh (649 LOC), doctor.sh (221), grkr-project-status.sh (189), grkr-templates.sh (317), grkr-task-slug.sh (17)
- Launcher bin/grkr updated in places to call Gleam CLIs (e.g. progress, task_slug, issue_provider)

**Design & Spec artifacts (canonical):**
- spec/parts/ (41 files): 00-overview.md, 01-goal.md, ..., 07-supervisor.md, 09-main-loop-contract.md, 15-phase-3-detect-and-process-robot-comments.md, 17-issue-workflow-overview.md, 23-refusal-flow.md, 36-cleanup-policy.md, 39-recommended-implementation-order.md (1-5 covered, 6-12 backlog: implement-or-refuse, refusal worker, implement, test, comment scan, PR resolve, cleanup), + many more. `spec/spec.md` is generated index. (sync run in t_767a0b08)
- Root: supervisor-design-final.md (421 LOC, detailed final design: 10-module structure, exact types for JobKey/ActiveJob/Phase/SupervisorConfig/SupervisorError, FFI specs for process/fs/exec etc., logging format, active_jobs.json schema; GitHub-only), supervisor-synthesis.md, gleam-migration-patterns.md (extracted module splits, CLI dispatch, FFI patterns from existing v2 code for reuse in supervisor)
- Historical research archived under .grkr/archive/

**Current capabilities (what runs today):**
- Full GitHub issue picker via live gh GraphQL + Gleam decode/selector (priority, age ordering, active job exclusion) -- wired end-to-end in thin bin
- Refusal flow: generates refusal.md, posts checkpoint (idempotent), updates progress.json, optional Backlog move via gh; cli emits exact shell KEY=val
- Supervisor: startup recovery of dead jobs (pid check + lock purge), stale lock purge, active_jobs.json read/write (atomic), per-entity locking (flock compat via FFI), tick loop with max_ticks/fail_phases test hooks, structured logging to main.log/loop.log/jobs/*.log ; phase error boundaries (supervisor survives); phases dispatch (sync via worker, scan_pr using resolve_pr list+filter, scan_comment prep with GitHubComment/processed state per spec/15, pick + full scheduler wired for record_active_job + spawn live, reap, cleanup) 
- PR conflict resolution end-to-end via Gleam in worktrees
- Issue execution: research/plan checkpoints, decision gate (proceed/refuse), refusal path, worktree isolation (.grkr/worktrees/<slug>/), progress tracking, sharded logs for large impl transcripts, test/build commands, PR creation/update, completion
- Linear: experimental provider (with safe credential handling, no direct token use for app creds), discovery CLIs, opt-in live E2E
- All per specs, with thin shell adapters for doctor/config sourcing, env, output emission (key=value shell safe)

**Remaining (from 39-order.md + kanban + design):**
- Full comment scanning + @:robot: command handling + worker-handle (phase 3 per spec/15; prep for GitHubComment/processed state landed in state/types, stub in scan_comment)
- Thinning for grkr-issue-workflow.sh (649 LOC) and remaining issue workflow stages (implement, test, decision gate)
- Full PR review of open slices, e2e validation, test+docs+sync
- Cleanup polish, stale worktree/lock handling per 36-policy (current stubs list counts)
- Old lock/build hygiene as needed (none found in .grkr/ this run)
- Then backlog items 6+: implement-or-refuse gate full, etc.
- Linear provider full execution path

**Traceability & process:**
- Kanban: this task t_767a0b08 (test+docs+sync: fixed remaining dupe "phase_started" log in supervisor/phases.gleam (refactor leftover), ran full `gleam build` (clean) + `gleam test` (228 passed, 0 failures); updated docs/gleam-migration.md + README with current LOCs (phases 500 then; 517 post-wiring, all bins thin 18/40/43/57/57), what runs (phases: sync/pick/scan_pr/scan_comment/reap/cleanup), remaining; executed scripts/sync-spec.sh (refreshed index); verified no file >1000 LOC via wc (max phases 500, resolve_pr/main 426, grkr-issue-workflow 649, all others <400); no old locks in .grkr/locks/ or .grkr/ (build/ only current); added this note). Prior: t_61c5af7b (phases impl), t_3ded288d (commit), t_9024ff95 (cleanup), t_d5e8a0a9 etc.
- Git: uncommitted before this (scheduler new + phases/state/types wiring for scheduler+comment prep + docs/README/audit); our edits: docs + README updates + hygiene append (no code changes in this task)
- Follows AGENTS.md strictly: files <=1000 LOC, spec/parts/ canonical (sync run), update README on functional/docs changes, preserve bin/ shell, prefer split specs.
- During this run: oriented via kanban_show(t_20695489), read AGENTS.md + spec/parts/ (00,07,08,09,15,17,36,39 etc), supervisor-design-final.md, supervisor-synthesis.md, gleam-migration-patterns.md, docs/gleam-migration.md, README.md, current sources (phases/state/types/scheduler), git status, wc, then build/test, edits, sync, hygiene append, complete.
- No user-facing workflow changes — entrypoints (robot-main.sh, grkr --issue, worker-*.sh) and config remain identical; Gleam is internal thick logic + thin adapters.

See README.md (updated in same task) for usage details and cross-refs. Expand this doc as more slices land.

This update in t_20695489 per kanban lifecycle (orient via kanban_show, reads of spec/parts + AGENTS, build/test, scheduler wiring verification + prep, docs/README edits, spec sync, LOC+hygiene audit, complete with metadata).

**No user-facing workflow changes yet** — entrypoints (robot-main.sh, grkr --issue, worker-*.sh) and config remain identical; Gleam is internal thick logic + thin adapters.

---

**Prior update sections preserved for history:**

**Update in commit task t_3ded288d (2026-05-23):**
- Staged + committed ... (refusal fixes, bin thins, docs, test) to v2 branch + push

(Older sections from t_d5e8a0a9, t_9024ff95 etc. follow in original; kept for traceability.)

**Update for t_767a0b08 (2026-05-23):**
- Oriented with kanban_show, read AGENTS + listed spec/parts + design docs + source + git
- Fixed remaining issue: removed duplicate phase_started log in run_pick_and_schedule..._phase (leftover from phases extraction; now logs only from run_phase + specific)
- Confirmed `gleam build` clean + 228/228 tests pass (no warnings)
- Updated this file + README.md high-level snapshot/remaining for phases impl, latest LOCs, thins, recent cards
- Ran scripts/sync-spec.sh (updated spec/spec.md index + parts/README.md)
- Verified no file >1000 LOC (wc on *.gleam + *.sh), no old locks to clean (.grkr/ empty of runtime state)
- Handoff: changed_files=[docs/gleam-migration.md, README.md, src/grkr/supervisor/phases.gleam (fix)], tests_run=228, decisions=["remove dupe log to clean phases impl"], sync_result="index refreshed"
- Per AGENTS: post functional (phases), updated README + this, ran sync harness, LOC audit

This completes the test+docs+sync per task spec and kanban lifecycle.


**Hygiene note from t_32b4ad11 (2026-05-24, cleanup lane, GitHub-only v2):**
- Prep work for purging superseded kanban workspace t_e2503a20 (4.5M stale grkr-v2 copy at commit 91af723 from May23, now divergent from active ws)
- Full safety verification (lsof/ps/db/git/diff/gleam build clean) documented in .grkr/audit-cleanup.md
- scripts/sync-spec.sh run (no change); gleam build verified clean
- Per kanban-worker: documented ready-to-run rm + post-steps; blocked for review-required (terminal safety on destructive rm -rf; see t_980b7473 precedent and t_075882be audit)
- Added detailed prep note to .grkr/audit-cleanup.md (changed file)
- No user-facing workflow or code changes; just board/kanban hygiene reclaim (~4.5M space, part of ~14MB audit target)
- References: AGENTS.md (update README on changes), spec/parts/36-cleanup-policy.md, task t_32b4ad11 body
- This note added here + to README.md for traceability per AGENTS + task acceptance
- Future: after purge + human exec, re-audit and mark reclaim complete in cleanup lane

See .grkr/audit-cleanup.md for full before/after evidence, commands, and handoff metadata.


**Update for t_20695489 (2026-05-24 test+docs+sync):**
- Oriented with kanban_show(t_20695489), read AGENTS + listed spec/parts + design docs + source + git
- Confirmed `gleam build` clean + 228/228 tests pass (no warnings)
- Updated this file + README.md high-level snapshot/remaining for scheduler wiring, latest LOCs (phases 517, scheduler 130 new, state 245, types 181), recent cards (t_58ea0e02 scheduler, t_78a7818e prune, PR#79 reviews)
- Ran scripts/sync-spec.sh (updated spec/spec.md index + parts/README.md; 41 parts)
- Verified no file >1000 LOC (wc on *.gleam + *.sh), .grkr/ clean of runtime state
- Appended hygiene note to .grkr/audit-cleanup.md
- Handoff: changed_files=[docs/gleam-migration.md, README.md, spec/spec.md, .grkr/audit-cleanup.md], tests_run=228, tests_passed=228, sync_result="index refreshed (41 parts)", decisions=["scheduler now wired in pick phase (real spawn vs stub)", "prep state fns + GitHubComment type for upcoming scan_comment per spec/15", "docs/readme updated per AGENTS post-functional (scheduler)"]
- Per AGENTS: post functional (scheduler wiring + state prep), updated README + this, ran sync harness, LOC audit

This completes the test+docs+sync per task spec and kanban lifecycle.

**Update for t_55147911 (2026-05-24 post t_65d650b7 review + follow-up fixes):**
- Oriented with kanban_show(t_55147911) + parent t_65d650b7 (review found docs staleness gap #2 in main snapshot vs post-scheduler-wiring state)
- Read AGENTS.md, spec/parts/07/09/15/36/39, supervisor-design-final.md, gleam-migration.md, README, current sources (git HEAD for exact 517/130/245/181 LOCs + GitHubComment prep), git status/diff, prior cards
- Re-verified `gleam build` clean (0.08s, no warnings on review state) + `gleam test` 228 passed, 0 failures (via temp stash of current lock-fix uncommitted changes in phases/state/types for clean verify; no change from prior)
- Updated this file main snapshot sections (small explicit): supervisor module list with exact LOCs (phases 517, scheduler 130, state 245, types 181 + new GitHubComment/processed fns), phases desc (full scheduler wired in pick_and_schedule for record+spawn live vs stub), capabilities (updated supervisor bullet for full scheduler + scan_comment prep), remaining (scheduler item removed, comment prep noted)
- Small 6-line refresh to README.md "Gleam v2 Migration Progress" high-level snapshot + traceability for "supervisor phases + scheduler landed" post review
- Verified no file >1000 LOC (wc on project *.gleam + *.sh excluding build/: max test 754, thick shell 649, others <400)
- Ran `scripts/sync-spec.sh` (no spec touch expected or performed; index unchanged)
- Added note: "post t_65d650b7 review + follow-up fixes"
- No code changes (per AGENTS.md small explicit only for docs chore); uncommitted code changes from sibling lock fix card left as-is
- Handoff: changed_files=[docs/gleam-migration.md, README.md], tests_run=228, tests_passed=228, decisions=["docs snapshot synced to review-time state (phases 517 etc, full scheduler wired, GitHubComment prep)", "README high-level refreshed for supervisor+scheduler", "build/test re-verified clean on 517 state", "no spec sync needed"], sync_result="none (no spec changes)"
- Per AGENTS: post functional (scheduler wiring in prior), updated README + this, ran sync (noop), LOC audit, traceability to t_65d650b7 + t_17c4b022
- Posted summary comment to parent t_65d650b7 thread

This completes the docs refresh per task spec and kanban lifecycle.
