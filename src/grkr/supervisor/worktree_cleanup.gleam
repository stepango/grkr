//// worktree_cleanup.gleam
//// Classification + prune for stale worktrees per spec/parts/36-cleanup-policy.md
//// and .grkr/supervisor-cleanup-policy.md. Small module, uses existing ffi.
//// Refusal-safe: preserves task dirs/checkpoints; only prunes worktrees post-refusal commit.

import gleam/list
import gleam/string
import grkr/supervisor/ffi
import grkr/supervisor/types as t

/// Classify a single worktree dir name (basename) against policy.
/// Returns tuple (should_remove, reason) for logging.
pub fn classify_worktree(
  name: String,
  mtime: Int,
  now: Int,
  ttl_seconds: Int,
  is_active: Bool,
  has_refusal_checkpoint: Bool,
) -> #(Bool, String) {
  case is_active {
    True -> #(False, "active")
    False ->
      case has_refusal_checkpoint {
        True -> #(False, "refusal_checkpoint")
        False -> {
          let age = now - mtime
          case string.contains(name, "failed") || string.contains(name, "error") {
            True ->
              case age > ttl_seconds {
                True -> #(True, "failed_ttl_expired")
                False -> #(False, "failed_fresh")
              }
            False ->
              // completed or stale: >1h per policy
              case age > 3600 {
                True -> #(True, "completed_or_stale_ttl")
                False -> #(False, "fresh")
              }
          }
        }
      }
  }
}

/// Prune eligible worktrees under worktrees_dir.
/// Returns count removed. Never touches active or refusal-protected.
/// Uses ffi.stat_mtime + remove_dir_recursive.
pub fn prune_stale_worktrees(
  config: t.SupervisorConfig,
  active_jobs: List(String),
  refusal_checkpoints: List(String),
) -> Result(Int, String) {
  case ffi.list_files(config.worktrees_dir) {
    Error(e) -> Error(e)
    Ok(entries) -> {
      let now = ffi.unix_seconds()
      let to_prune =
        list.filter(entries, fn(name) {
          case string.starts_with(name, ".") {
            True -> False
            False -> {
              let full = config.worktrees_dir <> "/" <> name
              let mtime = case ffi.stat_mtime(full) {
                Ok(m) -> m
                Error(_) -> 0
              }
              let is_active = list.contains(active_jobs, name)
              let has_refusal = list.any(refusal_checkpoints, fn(cp) {
                string.contains(name, cp)
              })
              let #(remove, _reason) =
                classify_worktree(
                  name,
                  mtime,
                  now,
                  config.worktree_ttl_seconds,
                  is_active,
                  has_refusal,
                )
              remove
            }
          }
        })

      let removed =
        list.fold(to_prune, 0, fn(acc, name) {
          let full = config.worktrees_dir <> "/" <> name
          case ffi.remove_dir_recursive(full) {
            True -> acc + 1
            False -> acc
          }
        })

      Ok(removed)
    }
  }
}
