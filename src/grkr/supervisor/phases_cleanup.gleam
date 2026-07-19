//// phases_cleanup.gleam
//// CleanupStaleWorktrees phase (purge locks, compact comments, prune via worktree_cleanup).
//// Split out from phases.gleam for t_94976f9c LOC hygiene (thin dispatcher).
//// Exact calls, active_jobs keys, refusal protection, counts, log strings preserved.
/// Uses shared phases_log. Zero behavior change.
//// Per spec/parts/36-cleanup-policy + 09.

import gleam/dict
import gleam/int
import gleam/list
import gleam/string

import grkr/supervisor/ffi
import grkr/supervisor/phases_log as log
import grkr/supervisor/recovery
import grkr/supervisor/state
import grkr/supervisor/types as t
import grkr/supervisor/worktree_cleanup

pub fn run(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  // Purge stale job locks (complements startup; always safe)
  let _ = case recovery.purge_stale_lock_files(config) {
    Ok(purged) ->
      log.log_info(
        config,
        "cleanup_stale_worktrees",
        "-",
        entity,
        "purged_stale_locks=" <> int.to_string(purged),
      )
    Error(_) -> Nil
  }
  // compact processed_comments per spec/parts/36 (size cap)
  let _ = state.compact_processed_comments(config.processed_comments_file, 500)
  // actual TTL prune wired to live active_jobs + refusal-protected task slugs from progress/refusal.md
  let active_job_keys = case state.read_active_jobs(config.active_jobs_file) {
    Ok(jobs) -> dict.keys(jobs)
    Error(_) -> []
  }
  let refusal_dirs =
    worktree_cleanup.collect_refusal_protected_tokens(config.tasks_dir)
  let _ = case worktree_cleanup.prune_stale_worktrees(config, active_job_keys, refusal_dirs) {
    Ok(n) -> log.log_info(config, "cleanup_stale_worktrees", "-", entity, "pruned_worktrees=" <> int.to_string(n))
    Error(e) -> log.log_error(config, "cleanup_stale_worktrees", "-", entity, "prune_failed=" <> e)
  }  // Worktree prune per spec/parts/36-cleanup-policy (every ~10 ticks, >1h TTL for done, failed>configured TTL, prune stale, purge locks, compact processed comments)
  let wt_count = case ffi.list_files(config.worktrees_dir) {
    Ok(files) ->
      list.length(list.filter(files, fn(f) { !string.starts_with(f, ".") }))
    Error(_) -> 0
  }
  // Job log retention: count current logs (retention policy: supervisor keeps recent; old purged by external cron if needed)
  let log_count = case ffi.list_files(config.job_logs_dir) {
    Ok(files) ->
      list.length(list.filter(files, fn(f) { string.ends_with(f, ".log") }))
    Error(_) -> 0
  }
  let _ =
    log.log_info(
      config,
      "cleanup_stale_worktrees",
      "-",
      entity,
      "worktree_count=" <> int.to_string(wt_count) <> " job_log_count=" <> int.to_string(log_count) <> " stale_locks_purged=done",
    )
  t.Success
}
