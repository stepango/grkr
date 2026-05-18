# Supervisor Research Synthesis for Gleam v2 Migration (GitHub-only)

**Synthesize task:** t_1ec1ab1c
**Date:** 2026-05-17
**Parents:** t_b84ae75f (T1: current shell supervisor bin/robot-main.sh + tests), t_758e53b9 (T2: spec/parts research + summary.md), t_619dc89f (T3: Gleam patterns/FFI from sync_main/resolve_pr/github_picker/issue_provider/progress/task_slug/refusal)
**Children:** t_e396dd70 (design: module structure + API), t_42d616ef (test+docs+sync), t_f5d39df3 / t_3b98efb4 (impl slices), t_22d401c1 (archived design)

## Executive Summary

The supervisor is the long-running orchestrator (`robot-main.sh` ~519 LOC) that coordinates the automation loop: recovery, sync_main, PR/comment scans (stubs), issue pick+schedule, reap, cleanup. It owns state/locks/logs under `.grkr/`, enforces serialization via flock + active_jobs, gates on doctor validation, supports MAX_TICKS/FAIL_PHASES for tests, never dies on worker failures.

T1 extracted full production logic + exact match to specs.
T2 confirmed no gaps vs spec/parts/ (07-supervisor, 09-main-loop-contract, 33-locking, 35-failure, 36-cleanup, 10-validation, phases 13-16, etc.).
T3 extracted proven Gleam patterns: module splits, CLI dispatch, FFI (exec/fs with flock fd, json, env, process), thin shell wrappers, shell sourcing output, Result-based errors, test bypass via GLEAM_ENV.

**Concrete proposal:** Reimplement in Gleam at `src/grkr/supervisor/` (8-10 modules, each <~400 LOC) with **thin** `bin/robot-main.sh` wrapper (~20 LOC). Preserve 100% external behavior (logs, JSON schema, lock files, exit codes 0/1/2/64/75, env contracts, task slugs, recovery semantics) for zero-downtime test compatibility and gradual cutover. GitHub-first (gh + Project V2 via github_picker; Linear via existing issue_provider).

No contradictions; production behavior to replicate exactly per project goal (Gleam thick, shell thin wrappers/tests).

## Consolidated Findings

### T1: Current Shell Supervisor (bin/robot-main.sh)
- Structure: no `set -e`, explicit paths; doctor_init + load_runtime_config + ensure_layout + refresh_validation (VALIDATION_OK gate).
- Logging: structured `log_event` (k=v escaped) to main.log/loop.log/jobs/<key>.log
- State: `active_jobs.json` (atomic tmp+jq+mv); record/remove/count by prefix (issue:*:execution)
- Recovery: at loop start + reap: kill -0 check, rm lock + del entry for dead; purge_stale_lock_files (every 10 ticks, flock -n test)
- Locking: flock -n 9>locks/<name>.lock ; 75 = busy (treated as skip for some phases)
- Phases (in fixed order, error boundary per phase):
  - sync_main: worker-sync-main.sh (already Gleam)
  - scan_prs / scan_comments: stubs (pending)
  - pick_issue: worker-pick-issue.sh (heavy jq/gh now) -> if selected, schedule bg `(flock ...; bin/grkr --issue N) &` under per-issue lock, record pid+meta
  - reap: recover
  - cleanup: purge if %10==0
- Schedule: prep lock/log, bg spawn under flock, record_active_job
- Sleep: calc remaining = INTERVAL - elapsed
- Test hooks: GRKR_MAX_TICKS, GRKR_FAIL_PHASES csv, mocks
- Matches specs exactly for GitHub path.

### T2: Spec Requirements (from parts/)
- Fixed phase order + sleep to wall-clock interval.
- Resilience: per-phase error boundary, supervisor survives worker non-0; workers can use set -euo.
- Locking/concurrency: entity locks (pr-N, issue-N, comment-*, main, prs, etc.); at most 1 active issue exec; dead recovery + orphan purge.
- State model: active_jobs + processed_comments + caches under .grkr/state/
- Failure: transient retry next tick; permanent no hot-retry; refusal is success path (separate).
- Cleanup: locks, worktrees (TTL), json compact; per 36-policy.
- Validation: doctor at startup + refresh; mutating disabled if fail.
- Logging: multi-target structured.
- GitHub Project V2 for pick; gh for PRs/comments.

### T3: Gleam + FFI Patterns (proven in v2 modules)
- **Module split (canonical, keeps files small/testable):** types.gleam (pure domain + parsers), config.gleam (env + fixtures), main.gleam (CLI entry, test bypass, run()), domain (decoder/selector/github/git/codex/client/query/assessment), ffi.gleam (reexports @external), <name>_ffi.mjs (thin JS glue).
- **CLI patterns:** main() { if GLEAM_ENV=test {Nil} else run_cli() }; argv via JS FFI (slice(2)); subcommands; shell_quote for KEY="val\n" output (for sourcing in pick/task-slug); exit 0/1/2/75/64; public run() for tests/other Gleam.
- **FFI (JS target):** execFileSync for gh/git/codex (cwd=GRKR_ROOT); fs.openSync + spawnSync flock with fd passing hack (stdio map to 3); Map<lock,fd> for held; json parse/get_field/walk; env/argv; future process.spawn_detached + unref for bg, process.kill(pid,0) for alive.
- **Thin wrappers:** doctor.sh + [ -f config ] . config + exec gleam run -m grkr/xxx/main -- "$@"
- **State/locking in Gleam:** json_ffi + fs for atomic (tmp + renameSync); Result types.
- **Reuse:** task_slug.gleam, progress/* (checkpoints, but supervisor delegates), sync_main, resolve_pr (github.gleam patterns for PR scan), github_picker (for pick, once wired), issue_provider (Linear).
- **Error:** Result<Ok, Err> + use/result.try ; never let uncaught kill long-running main.
- **Pitfalls to solve for supervisor:** flock fd lifetime in bg spawn; detached pid that outlives tick; cross-tick PID check; atomic JSON; sleep precision; preserve 75/64 codes.

## Concrete Proposal for src/grkr/supervisor/

**Directory:** src/grkr/supervisor/ (new)

**Modules (8-10, each <400 LOC, split if needed):**
1. types.gleam — JobKey (pr:ID:task, issue:ID:execution, comment:ID:cmd), ActiveJob {pid, entity_type, entity_id, lock_name, task_slug, started_at, project_item_id?}, Phase (SyncMain | ScanPRs | ...), SupervisorConfig, LockResult, PhaseResult, SupervisorError
2. config.gleam — load() -> Result(SupervisorConfig, Err) [env after wrapper: REPO, LOOP_INTERVAL_SECS, GRKR_ROOT, MAX_TICKS?, FAIL_PHASES, PROJECT_*, etc.]
3. main.gleam — pub fn main() -> Nil; run() -> Result(Nil, Err); CLI for --help / sub if needed; test bypass; load config + run_loop
4. loop.gleam — run_loop(config) { loop_count=0; while true { tick_start=now(); ... phases; sleep_remaining; if max_ticks break } }
5. recovery.gleam — recover_dead_jobs(phase_name), purge_stale_lock_files (every N)
6. locking.gleam — acquire_lock(path), release_lock(path), is_held (FFI)
7. state.gleam — read_active_jobs() -> Dict(JobKey, ActiveJob), record_active_job(...), remove_active_job(key), count_active_by_prefix("issue:*:execution"), job_key_lock_name(key)
8. logging.gleam — log_event(phase, job?, entity?, msg) [builds structured, append via FFI to .grkr/logs/... ]
9. phases.gleam — run_phase(phase), phase_sync_main (call worker or inline), phase_pick_and_schedule_issue (use picker or parse worker-pick-issue output), phase_schedule_*(key, cmd), phase_reap, phase_cleanup, phase_scan_prs (future: github pr list + filter), phase_scan_comments
10. scheduler.gleam — schedule_and_spawn(job_key, cmd_list, lock_name) -> Result(Pid, Err) [prep, bg spawn, record]

**FFI (new or consolidated):**
- Extend/create src/grkr/ffi/ (recommended post-supervisor to dedupe):
  - process.mjs : spawn_detached(cmd, args, opts={cwd, env, detached:true, stdio:'ignore'}) -> pid; is_alive(pid); kill(pid)
  - fs.mjs extensions: atomic_write (tmp+rename), append_log, recursive_rm?
  - Keep existing per-module for now (non-breaking)
- Other: sleep_ffi, log_append

**CLI entry + thin bin/robot-main.sh wrapper (preserve conventions):**
```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/doctor.sh"
doctor_init
if [ -f "$GRKR_CONFIG_FILE" ]; then . "$GRKR_CONFIG_FILE"; fi
export GRKR_ROOT=... MAIN_BRANCH=... LOOP_INTERVAL_SECS=...
cd "$PROJECT_ROOT" || exit 1
# optional arg validation
exec gleam run -m grkr/supervisor/main "$@"
```
(Doctor + config sourcing stay in shell; Gleam gets clean env. Keep current robot-main.sh as fallback until Gleam passes tests.)

**Integration with existing:**
- sync_main: call via worker or direct gleam run -m grkr/sync_main/main under lock
- pick: initially parse stdout from worker-pick-issue.sh (SELECTED=...); later full migration to github_picker in Gleam
- PR/comment scans: new using resolve_pr/github.gleam patterns + gh FFI
- Workers (grkr --issue, resolve-pr): unchanged, still bg spawned under locks
- Progress: supervisor doesn't post checkpoints (workers do via progress/cli)
- task_slug: use grkr/task_slug/cli

**Test strategy:**
- Reuse/extend `test/robot-main-supervisor.sh`, `test/robot-main-phase-failure.sh`, `test/robot-main-schedules-issue.sh`: run thin wrapper with GRKR_MAX_TICKS=5, GRKR_FAIL_PHASES=..., fixture PATH, assert phase order, logs, active_jobs.json, locks, recovery (kill pids), validation skip, cleanup %10, no exit on worker fail.
- Gleam unit: `gleam test` in supervisor/ for pure fns (parsers, counts, sleep calc, phase dispatch, Result paths)
- FFI/integration: node test harness or full e2e with mocks (gh fixtures as in picker)
- Keep bash supervisor live in parallel for migration; switch when all tests green.
- Spec sync + README update in follow-up card.

## Key Decisions & Recommendations
- **GitHub-only first**: full focus on gh/project V2; Linear via issue_provider/config already present but secondary.
- **Preserve shell contracts exactly**: enables drop-in replacement without touching tests/workers.
- **Error boundaries everywhere**: supervisor loop and each phase use Result/try; log ERROR + continue.
- **FFI first for supervisor**: process spawn/alive/lock must be solid before loop (test on macOS host).
- **Consolidate FFI later**: after this slice, refactor duplicated code in other modules to shared grkr/ffi/
- **Impl order (for design/impl cards)**: 1. skeleton + FFI + basic loop/MAX_TICKS (testable), 2. recovery+locking+state, 3. sync phase, 4. pick+schedule (compat), 5. scans + cleanup + polish.
- **File/LOC discipline**: per AGENTS.md; split scheduler/phases if >900.
- **No spec edits**: research only; update README + run scripts/sync-spec.sh in test+docs card.
- **Risks**: flock fd + detached spawn in JS (test thoroughly); PID lifecycle; atomic writes under JS; time precision; gradual migration safety (parallel run).

## Deliverables
- This `supervisor-synthesis.md` (durable artifact in workspace)
- Detailed handoff comment posted to t_1ec1ab1c (this card)
- Research fully synthesized from T1+T2+T3; design card t_e396dd70 has concrete input (this + patterns.md + archived research-summary + specs)
- No code / functional changes (research + synthesis only); ready for design approval then impl parents
- References to archived large docs preserved for history

## References
- `.grkr/archive/supervisor-research-summary.md` (full T1+T2 extraction + proposal)
- `gleam-migration-patterns.md` (T3 FFI/CLI/module patterns + handoff)
- `spec/parts/{07-supervisor.md,09-main-loop-contract.md,33-locking-and-concurrency.md,35-failure-handling.md,36-cleanup-policy.md,10-startup-validation.md,02-core-requirements.md,11-state-model.md,12-worktree-model.md,13-16 phases,34-logging,39-recommended-order,...}`
- `bin/robot-main.sh`, `test/robot-main-*.sh`
- `src/grkr/{sync_main,resolve_pr,github_picker,issue_provider,progress,task_slug,refusal}/**/*.gleam` + `*_ffi.mjs`
- `AGENTS.md`, `docs/gleam-migration.md`, `README.md`
- Prior kanban threads for t_758e53b9, t_619dc89f, t_b84ae75f

**Ready for handoff to design (t_e396dd70) and implementation.**

(End of synthesis for t_1ec1ab1c. GitHub-only. AGENTS.md compliant. No files >1000 LOC.)

