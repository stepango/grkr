# Supervisor Cleanup Policy Decision (spec/parts/36)

## Classification Rules for Worktrees under config.worktrees_dir

1. **Completed worktrees**: Remove if mtime > 1 hour (3600s) and no active job reference in state.active_jobs. Matches "remove completed worktrees older than 1 hour".

2. **Failed worktrees**: Remove if mtime > config.worktree_ttl_seconds (default 3600s) and job marked failed in state. Per "remove failed worktrees older than configured TTL".

3. **Refusal-safe handling** (per spec):
   - Task directories (under .grkr/tasks/ or equivalent) MUST be preserved for refused issues.
   - Refusal checkpoints in state (processed_comments, recovery checkpoints) MUST remain.
   - Worktrees for refused issues: removable ONLY after refusal is committed to state + comments (i.e., after run_scan_comment_commands_phase has processed the refusal). Worktree prune may happen immediately post-commit; task dir and checkpoints stay forever.

4. **Stale worktrees** (no matching job state): Prune if older than TTL, unless refusal checkpoint present.

5. **Active / in-progress**: Never touch worktrees while the job key is still listed in `active_jobs.json` (see §6). Lock + PID recovery runs separately each tick.

## 6. Active jobs stale TTL (`active_jobs.json`)

Spec anchors: `spec/parts/36-cleanup-policy.md` (cleanup polish / #21), `spec/parts/33-locking-and-concurrency.md` §25.3 (inspect `active_jobs.json` each loop), `spec/parts/11-state-model.md` (job keys + idempotency). Gleam gap tracked in `recovery.gleam` header: dead-PID recovery exists; **TTL purge for live PIDs** is this section.

### 6.1 Config

| Field | Env override | Default | Notes |
|-------|----------------|---------|-------|
| `active_job_ttl_seconds` | `ACTIVE_JOB_TTL_SECONDS` | **86400** (24 hours) | Seconds a job may remain in `active_jobs.json` while still “active”. Mirrors the 24h concern in `recovery.gleam` GAPS. Distinct from `worktree_ttl_seconds` (default 3600). |

Load into `SupervisorConfig` alongside `worktree_ttl_seconds` (`config.gleam`). User-facing env name matches shell-style `WORKTREE_TTL` pattern: document `ACTIVE_JOB_TTL_SECONDS` in README only when the implement card wires the env (optional for this doc-only card).

### 6.2 `ActiveJob` time basis

Each entry (`types.ActiveJob`) includes `started_at: String`, set at schedule time to **UTC ISO-8601** (same format as supervisor logs, e.g. `2026-05-17T12:00:00Z`) via `state.record_active_job` / `ffi.utc_timestamp()`.

**Age** for TTL:

```
age_seconds = now_unix - parse_utc_iso(started_at)
```

- **Parse**: ISO-8601 UTC string → Unix seconds. Implement in FFI or Gleam; must accept the exact strings the supervisor writes today.
- **Invalid / empty `started_at`**: **Do not TTL-purge** that entry. Log `WARN` with `active_job_started_at_invalid=true job=<key>` and rely on dead-PID recovery (`is_alive(pid) == false`) only. Avoids destructive purge on legacy or hand-edited JSON.

### 6.3 When to remove an entry (purge criteria)

Run TTL recovery in the **same places as dead-PID recovery**: start of supervisor (`loop.gleam` startup) and each `reap_finished_jobs` phase (`phases.gleam`), before scheduling new work.

For each `(job_key, ActiveJob)` in `active_jobs.json`:

1. **Dead PID** (existing): `!is_alive(pid)` → remove via `recover_dead_jobs` (unchanged). Log `stale_job pid=… recovered=true reason=dead_pid`.

2. **TTL expired** (new): `is_alive(pid)` **and** `age_seconds > active_job_ttl_seconds` → **stale TTL purge**. Log `WARN` `stale_job pid=… recovered=true reason=stale_ttl age_seconds=… ttl=…`.

3. **Hung lock heuristic** (new, **OR** — does not require TTL): `is_alive(pid)` **and** `check_stale_lock(lock_path)` is **true** (no live `flock` holder) **and** `age_seconds >= 300` (5-minute post-`started_at` grace so a newly spawned worker can acquire its lock) → purge. Log `reason=stale_hung_lock`. Covers zombie PIDs and orphaned rows where the worker exited without reaping but `kill -0` still succeeds.

If both (2) and (3) apply, log `reason=stale_ttl` when `age_seconds > active_job_ttl_seconds`, else `stale_hung_lock`.

**Do not** SIGKILL/SIGTERM the PID as part of cleanup; only remove state + unlink lock file (same contract as dead-PID recovery). Optional future: signal hung workers — out of scope for #21 slice.

**Removal procedure** (identical to dead jobs):

1. Build `remaining` dict without purged keys.
2. `write_active_jobs_atomic` **first**.
3. On success, `unlink` per-job lock under `locks_dir` (resolve `lock_name` or derive from `job_key` like `recover_dead_jobs`).
4. On write failure: log `active_jobs_update_failed=true`, return `Error`, **do not** unlink locks.

**Requeue**: Do not auto-requeue on TTL purge (match current dead-PID behavior). Downstream pick/schedule may select the entity again per normal idempotency rules.

### 6.4 Logging

| Event | Level | Example `msg` fragment |
|-------|-------|-------------------------|
| No stale TTL jobs | INFO | `stale_ttl_jobs=0` (or fold into existing `stale_jobs=0` if combined with dead-PID pass) |
| TTL/hung purge | WARN | `stale_job pid=12345 recovered=true reason=stale_ttl` |
| Hung lock purge | WARN | `stale_job pid=12345 recovered=true reason=stale_hung_lock` |
| Invalid started_at | WARN | `active_job_started_at_invalid=true` |
| State IO failure | ERROR | `active_jobs_state_invalid=true` / `active_jobs_update_failed=true` |

Use `phase=startup` or `phase=reap_finished_jobs` to match the caller.

### 6.5 Refusal, checkpoints, and worktree protection

- **Refusal in flight**: Job keys like `issue:<n>:refusal` follow the **same TTL** as other jobs. TTL purge removes only the `active_jobs.json` row + lock; it does **not** delete refusal checkpoints, `processed_comments.json` entries, or task folders under `tasks_dir` (per §3 refusal-safe handling).
- **Refused issues (committed)**: Task dirs and refusal checkpoints remain forever; worktree removal is governed by §3–§5, not by active_jobs TTL alone.
- **Worktrees**: While a job key is in `active_jobs`, `worktree_cleanup` treats the linked worktree name as **active** (`is_active=true`) and will not prune (§5). Purging a stale TTL entry allows a later cleanup tick to classify/prune the worktree per §1–§4.
- **Picker / scheduling**: `github_picker` and supervisor phases must continue to treat keys present in `active_jobs` as “already running”; TTL purge is the escape hatch when `is_alive` lies (hung) or the worker outlives the TTL.

### 6.6 Implementation map (for `t_13484753`)

- Add `recover_stale_active_jobs_by_ttl` (or extend `recover_dead_jobs`) in `recovery.gleam`.
- Wire from `loop.gleam` startup + `phases.gleam` `run_reap_finished_jobs_phase`.
- Unit tests: mock `started_at`, TTL, `is_alive`, `check_stale_lock`; assert atomic write order and log reasons.
- No change to `active_jobs.json` schema.

## Implementation Notes
- Use ffi.stat_mtime + list_files in phases.gleam run_cleanup_stale_worktrees_phase (already partially wired in prior cards).
- recovery.gleam provides purge_stale_lock_files and refusal checkpoint helpers.
- state.gleam manages active_jobs, processed_comments, refusal markers.
- Criteria unambiguous from spec/parts/36-cleanup-policy.md; no human decision needed for classification.

This enables safe destructive prune in parent t_8f06d85c without risk to refusal state.
