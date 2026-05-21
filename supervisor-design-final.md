# Supervisor Gleam v2 Design Final (GitHub-only)

**Design task:** t_e396dd70
**Date:** 2026-05-17
**Based on:** supervisor-synthesis.md (t_1ec1ab1c), gleam-migration-patterns.md (t_619dc89f), .grkr/archive/supervisor-research-summary.md (t_758e53b9), spec/parts/ (07-supervisor.md, 09-main-loop-contract.md, 33-locking-and-concurrency.md, 35-failure-handling.md, 36-cleanup-policy.md, 10-startup-validation.md, 11-state-model.md, 34-logging-and-observability.md, 06-process-architecture.md, 08-worker-scripts.md, 13-16 phase slices, 02/03-core), bin/robot-main.sh (519 LOC), existing Gleam (github_picker/*, sync_main/*, resolve_pr/*, refusal/*, task_slug, progress), AGENTS.md, README.md, test/robot-main-*.sh
**Status:** Finalized. Ready for implementation parents (t_f5d39df3 main/loop, t_3b98efb4 recovery/locking/state, t_42d616ef test+docs+sync).

## Executive Summary

Reimplement the long-lived supervisor loop (currently bin/robot-main.sh) as thick Gleam logic in `src/grkr/supervisor/` (8-10 modules) with a **thin** `bin/robot-main.sh` wrapper (~25 LOC). Preserve 100% external contracts: logs, active_jobs.json schema, lock files/names, exit codes (0/1/2/64/75), env vars, job keys, recovery semantics, phase order, MAX_TICKS/FAIL_PHASES test hooks, doctor+config sourcing in shell.

GitHub-only for this slice (github_picker for pick; issue_provider/Linear remains secondary and out of core supervisor changes). No new credentials.

Follow AGENTS.md: files <=1000 LOC, spec/parts/ canonical (no edits here), run sync-spec.sh in follow-up, preserve bin/ as thin, update README in test+docs card.

## Exact Module Structure (src/grkr/supervisor/)

**Gleam modules (8-10, each <400 LOC; split phases/scheduler if needed):**
1. types.gleam — pure domain types + parsers (JobKey, ActiveJob, Phase, SupervisorConfig, SupervisorError, PhaseResult, LockResult, helpers)
2. config.gleam — load_runtime_config() from env + fixtures for tests
3. main.gleam — CLI entry (main/ run), test bypass, delegates to loop
4. loop.gleam — run_loop + tick orchestration (recovery, phases, sleep, max_ticks)
5. recovery.gleam — recover_dead_jobs, purge_stale_lock_files, pid checks
6. locking.gleam — acquire/release + with helpers (flock compat)
7. state.gleam — read/write active_jobs.json (atomic), record/remove/count, job_key utils
8. logging.gleam — log_event (structured, multi-target append)
9. phases.gleam — run_all_phases + per-phase impl (sync, pick compat, schedule, reap, cleanup, scan stubs)
10. scheduler.gleam — schedule_and_spawn (bg detached with flock cmd, record)

**Supporting .mjs (in same dir, copy proven patterns from sync_main/resolve_pr/github_picker):**
- cli_ffi.mjs — argv(), console_log, exit (for main if needed)
- env.mjs — get_env, get_with_default, argv (reuse or copy)
- exec.mjs — executable(cmd, args, input?) -> {exit_code, stdout, stderr} (for gh/git/doctor output capture, worker exec)
- fs.mjs — mkdir_p, acquire_lock/release_lock (exact flock -n fd3 + Map<fd> compat from sync_main/fs.mjs), atomic_write_json, append_log, read_text, write_text, exists
- process.mjs — spawn_detached(cmd, args, opts) -> Int (pid), is_alive(pid), kill(pid, sig?), sleep_seconds(secs)
- json_ffi.mjs — parse, get_field, decode_*, walk_path helpers (reuse from refusal/json_ffi.mjs or github_picker)

**No new shared grkr/ffi/ in this slice** (keep per-module to match existing; consolidate in future slice after supervisor lands).

**Entry:** thin bin/robot-main.sh sources doctor.sh + .grkr/config.sh then `exec gleam run -m grkr/supervisor/main "$@"`

**Reuse (no duplication):**
- github_picker/{config,types,decoder,selector} for future pure pick; initially parse worker-pick-issue.sh emit for compat
- sync_main/main (via worker-sync-main.sh or direct)
- resolve_pr patterns for future PR scan
- task_slug/cli for slug gen if needed
- progress/cli for worker checkpoints (supervisor does not post)
- refusal parse_implementation_decision if decision gate needed here (unlikely)

## Precise Types (types.gleam)

```gleam
import gleam/dict
import gleam/option.{type Option, Some, None}

pub type JobKey {
  PrConflict(number: Int)
  IssueExecution(number: Int)
  Comment(id: String)
  // Future: IssueRefusal(number: Int)
}

pub fn job_key_from_string(s: String) -> Result(JobKey, String) {
  // parse "pr:123:conflict-resolution" -> PrConflict(123)
  // "issue:42:execution" -> IssueExecution(42)
  // "comment:123456" -> Comment("123456")
  // etc. Normalize and error on unknown.
}

pub fn job_key_to_string(key: JobKey) -> String { ... }

pub fn job_key_lock_name(key: JobKey) -> String {
  // "pr-123", "issue-42", "comment-123456"
}

pub fn job_key_log_basename(key: JobKey) -> String {
  // "pr-123-conflict-resolution" or sanitized for filename (use existing sed logic via FFI or Gleam)
}

pub type ActiveJob {
  ActiveJob(
    pid: Int,
    entity_type: String,      // "issue" | "pr" | "comment"
    entity_id: String,        // "42" or comment id as string
    lock_name: String,        // "issue-42"
    task_slug: String,
    started_at: String,       // "2026-05-17T12:00:00Z" UTC ISO
    project_item_id: Option(String),
  )
}

pub type Phase {
  SyncMain
  ScanPrConflicts
  ScanCommentCommands
  PickAndScheduleIssueExecution
  ReapFinishedJobs
  CleanupStaleWorktrees
  SleepUntilNextTick
  // Internal for logging: StartupValidation, Supervisor
}

pub fn phase_to_string(p: Phase) -> String { ... }  // "sync_main", "pick_and_schedule_issue_execution" etc. exact match to shell logs

pub type SupervisorConfig {
  SupervisorConfig(
    repo: String,
    main_branch: String,
    loop_interval_secs: Int,
    grkr_root: String,
    grkr_dir: String,
    state_dir: String,
    locks_dir: String,
    logs_dir: String,
    job_logs_dir: String,
    worktrees_dir: String,
    tasks_dir: String,
    active_jobs_file: String,
    max_ticks: Option(Int),
    fail_phases: List(String),   // from GRKR_FAIL_PHASES csv
    validation_ok: Bool,
    project_owner: String,
    project_number: Int,
    status_field_name: String,
    todo_value: String,
    backlog_value: String,
    priority_field_name: String,
    priority_mode: String,       // from github_picker types
    priority_order: String,
    // Add any others surfaced by load (e.g. ENABLE_*, GRKR_GLEAM_PROJECT_ROOT)
  )
}

pub type SupervisorError {
  ConfigLoad(String)
  Io(String)
  ValidationFailed
  LockBusy                      // treat as success (75)
  PhaseFailed(phase: String, code: Int)
  Parse(String)
  SpawnFailed(String)
  Other(String)
}

pub type LockResult {
  Acquired
  Busy
  Error(String)
}

pub type PhaseResult {
  Success
  Skipped(reason: String)
  Failed(err: SupervisorError)
}
```

**State JSON schema (active_jobs.json):**
```json
{
  "issue:5:execution": {
    "pid": 12345,
    "entity_type": "issue",
    "entity_id": "5",
    "lock_name": "issue-5",
    "task_slug": "issue-5-foo",
    "started_at": "2026-...",
    "project_item_id": "ITEM_5"
  }
}
```
- Keys = job_key strings
- pid always present (Int)
- project_item_id optional in JSON

**Logging line format (exact):**
`2026-05-17T12:00:00Z INFO phase=pick_and_schedule_issue_execution job=issue:5:execution entity=issue/5 msg="scheduled_jobs=1 selected_issue=5 task_slug=..."`

Written to:
- $GRKR_DIR/logs/main.log
- $GRKR_DIR/logs/loop.log
- $GRKR_DIR/logs/jobs/<sanitized-job-key>.log (if job_key)

## FFI Specification (detailed, must be solid before loop)

**process.mjs** (new):
```js
import { spawn, execFileSync } from 'child_process';
import { Ok, Error } from '../../gleam.mjs';

export function spawn_detached(cmd, args, opts = {}) {
  const fullOpts = {
    detached: true,
    stdio: 'ignore',
    cwd: process.env.GRKR_ROOT || process.cwd(),
    ...opts
  };
  try {
    const child = spawn(cmd, args.toArray ? args.toArray() : args, fullOpts);
    child.unref();
    return child.pid || 0;
  } catch (e) {
    return 0;
  }
}

export function is_alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (_) {
    return false;
  }
}

export function kill(pid, signal = 'SIGTERM') {
  try {
    process.kill(pid, signal);
    return true;
  } catch (_) {
    return false;
  }
}

export function sleep_seconds(secs) {
  if (secs <= 0) return;
  try {
    execFileSync('sleep', [secs.toString()], { stdio: 'ignore' });
  } catch (_) {}
}
```

**fs.mjs** (supervisor copy/extend of sync_main/fs.mjs):
- Keep exact `acquire_lock(path)` / `release_lock(path)` using fd 3 + spawnSync("flock", ["-n", "3"]) + Map for held fds. Return {Ok: Nil} or Error.
- Add:
  - `atomic_write_json(final_path, content_string)`: write tmp + renameSync (no jq)
  - `append_log(path, line)`: appendFileSync(path, line + "\n")
  - mkdir_p, read_file_sync etc for config/state

**exec.mjs** (thin wrapper around execFileSync, cwd=GRKR_ROOT, for gh/git/doctor capture in config/validation/pick parse)

**json_ffi.mjs**: reuse or copy refusal pattern for parse + safe field access + decode primitives. Used for active_jobs read/write (Dict via manual or gleam/json later).

**Pitfalls to test on macOS host:**
- flock fd lifetime (only held in the JS process that acquired)
- detached spawn survives tick (unref + ignore stdio)
- cross-tick PID check (kill -0)
- atomic rename under load
- sleep precision for remaining interval
- cwd for all exec/spawn = GRKR_ROOT
- Large output from gh in pick (but delegated to worker for now)

## Key Public APIs (per module)

**main.gleam**
```gleam
pub fn main() -> Nil
pub fn run() -> Result(Nil, SupervisorError)
```

**config.gleam**
```gleam
pub fn load_runtime_config() -> Result(SupervisorConfig, SupervisorError)
pub fn load_for_test(base_dir: String, overrides: Dict(String, String)) -> Result(SupervisorConfig, SupervisorError)
```

**loop.gleam**
```gleam
pub fn run_loop(config: SupervisorConfig) -> Result(Nil, SupervisorError)
// internal: tick, sleep_remaining, phase dispatch with error boundary
```

**recovery.gleam**
```gleam
pub fn recover_dead_jobs(config: SupervisorConfig, context_phase: String) -> Result(Int, SupervisorError)  // recovered count
pub fn purge_stale_lock_files(config: SupervisorConfig) -> Result(Int, SupervisorError)
```

**locking.gleam**
```gleam
pub fn acquire_lock(path: String) -> Result(LockResult, SupervisorError)
pub fn release_lock(path: String) -> Bool
// phases use manual acquire / run / release with try
```

**state.gleam**
```gleam
pub fn read_active_jobs(path: String) -> Result(Dict(String, ActiveJob), SupervisorError)
pub fn write_active_jobs_atomic(path: String, jobs: Dict(String, ActiveJob)) -> Result(Nil, SupervisorError)
pub fn record_active_job(config, key: JobKey, pid: Int, etype, eid, lock, slug, proj_item: Option(String)) -> Result(Nil, SupervisorError)
pub fn remove_active_job(path: String, key: String) -> Result(Nil, SupervisorError)
pub fn count_active_issue_executions(jobs: Dict(String, ActiveJob)) -> Int
```

**logging.gleam**
```gleam
pub fn log_event(level: String, phase: String, job_key: Option(String), entity: Option(String), msg: String, config: SupervisorConfig) -> Nil
pub fn log_info(phase, job, entity, msg, config) { log_event("INFO", ...) }
pub fn log_warn / log_error similar
```

**phases.gleam** (core orchestration)
```gleam
pub fn run_all_phases(config: SupervisorConfig, tick_count: Int) -> Result(Nil, SupervisorError)

fn run_phase(config: SupervisorConfig, phase: Phase, tick: Int) -> PhaseResult
fn phase_sync_main(config) -> PhaseResult
fn phase_pick_and_schedule_issue_execution(config) -> PhaseResult
fn phase_reap_finished_jobs(config) -> PhaseResult
fn phase_cleanup_stale_worktrees(config, tick: Int) -> PhaseResult
// scan_* return stub "scheduled_jobs=0 worker_logic=pending"
```

**scheduler.gleam**
```gleam
pub fn schedule_and_spawn(
  config: SupervisorConfig,
  job_key: JobKey,
  entity_num: Int,
  task_slug: String,
  project_item_id: Option(String),
  worker_cmd: List(String),   // e.g. ["bin/grkr", "--issue", "5"]
) -> Result(Int, SupervisorError)  // returns pid
// builds full bash -c "flock -n 9 || exit 75; ... >> joblog 2>&1" 9>locks/xxx.lock
// spawn_detached, record, log
```

**Pick compat (in phases):**
- exec worker-pick-issue.sh (via executable FFI)
- capture stdout
- parse lines like "SELECTED=1", "ISSUE_NUMBER=5", "JOB_KEY=issue:5:execution", "TASK_SLUG=...", "PROJECT_ITEM_ID=..."
- if SELECTED && number && !active -> schedule

This reuses the entire GitHub Project V2 query + selection in bash for this slice.

## Thin Wrapper (bin/robot-main.sh)

Replace (or keep old as .bak) with:

```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/doctor.sh"
doctor_init
if [ -f "$GRKR_CONFIG_FILE" ]; then . "$GRKR_CONFIG_FILE"; fi

export GRKR_ROOT="${GRKR_ROOT:-$PWD}"
export MAIN_BRANCH="${MAIN_BRANCH:-main}"
export LOOP_INTERVAL_SECS="${LOOP_INTERVAL_SECS:-20}"
# ... export any other needed for Gleam

cd "${PROJECT_ROOT:-$PWD}" || exit 1

exec gleam run -m grkr/supervisor/main "$@"
```

Doctor + config sourcing stay in shell (proven). Gleam receives clean env + paths.

Keep existing robot-main.sh logic available during migration (e.g. mv or conditional).

## Test Strategy

**Integration (primary, reuse existing harnesses):**
- test/robot-main-supervisor.sh, robot-main-phase-failure.sh, robot-main-schedules-issue.sh
- Setup: tmpdir, copy bin/* + mocks (gh, git, codex, timeout, flock that succeed/fail as needed), write .grkr/config.sh + active_jobs.json fixture with dead pid, GRKR_MAX_TICKS=1, GRKR_FAIL_PHASES=..., PATH=tmp/bin
- Run the (updated) bin/robot-main.sh
- Assert: exit 0, logs contain expected phase=... msg=..., active_jobs.json empty after recovery, correct locks created/removed, per-job log, recovery "stale_job ... recovered=true", phase_failed for FAIL_PHASES mapped to 64 treated as phase success, no crash, sleep logged, cleanup %10 etc.
- Bg spawn: the mock runner_log captures the grkr --issue cmd.

**Gleam unit tests** (in test/ or supervisor/):
- job_key roundtrips + lock_name
- config load from env dict
- active job count / record / remove (Dict)
- phase dispatch + result mapping
- sleep calc remaining
- error boundary paths (Result)

**FFI / spawn / lock integration:**
- Manual node -e or gleam test that exercises process.mjs + fs.mjs
- macOS specific: verify flock fd, detached pid outlives, kill -0

**MAX_TICKS + FAIL_PHASES simulation** exactly as shell.

**Parallel migration safety:** old robot-main.sh can run alongside until tests green; switch by updating wrapper.

## Docs & Alignment

- This file: supervisor-design-final.md (root, <1000 LOC)
- Update docs/gleam-migration.md: add "supervisor design finalized (t_e396dd70); impl in progress (GitHub-only)"
- test+docs card (t_42d616ef): 
  - update README.md supervisor section + v2 note ("Gleam src/grkr/supervisor/ + thin bin/robot-main.sh")
  - run scripts/sync-spec.sh (no-op for spec but confirms)
  - add Gleam tests + assert in harness
- No spec/parts edits (design only)
- AGENTS.md followed: GitHub-only, thin bin/, file size discipline, canonical specs referenced, no credentials

## Recommended Impl Phasing (for child cards)

1. Skeleton + FFI (process/fs/exec/json) + main/loop/config skeleton + MAX_TICKS stub loop (testable, logs to stdout)
2. Recovery + locking + state + logging (pid check, atomic json, structured append, recover/purge)
3. Sync phase + basic pick compat (exec worker, parse emit, schedule stub)
4. Full schedule + reap + error boundaries + validation gate + sleep
5. Cleanup, scan stubs, polish, unit tests, full integration harness pass
6. Handoff to test+docs for README/sync + final validation

All phases use Result + explicit error logging; never let uncaught kill the supervisor.

## Key Decisions & Risks

- **Compat first (initial)**: worker-pick-issue.sh + emit parse for pick; **pure Gleam github_picker integration completed** in t_a0cbcd49 (direct pick_next() call from supervisor/loop pick phase, no emit parse, no dupe logic).
- **Spawn model**: bash -c wrapper string for flock redirect + worker cmd (matches shell exactly); supervisor never holds worker locks.
- **FFI ownership**: per-supervisor/ .mjs this slice (proven pattern); shared grkr/ffi/ after.
- **Config**: always via shell wrapper (doctor + sourcing) — Gleam never sources .sh
- **State**: Gleam Dict + atomic rename (no jq dependency in core path)
- **Risks (mitigated by tests)**: flock fd cross-process, detached lifecycle, PID reuse edge, time precision on sleep, 75/64 exit mapping.
- **Why this works**: 1:1 behavior replication + thin shell = zero-downtime cutover + full test coverage.

**Ready for implementation.** Use this + synthesis.md + patterns.md + robot-main.sh + spec/parts + existing Gleam modules as ground truth. Post this as kanban comment on t_e396dd70 and update children.

(End of design. GitHub-only. AGENTS.md compliant. All referenced research preserved in .grkr/archive/.)
