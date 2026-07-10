//// worktree_cleanup.gleam
//// Classification + prune for stale worktrees per spec/parts/36-cleanup-policy.md
//// and .grkr/supervisor-cleanup-policy.md. Small module, uses existing ffi.
//// Refusal-safe: preserves task dirs/checkpoints; only prunes worktrees post-refusal commit.

import gleam/list
import gleam/string
import grkr/refusal/checkpoint
import grkr/supervisor/ffi
import grkr/supervisor/types as t

/// True when progress.json shows refusal/decision=refuse without implement_or_refuse.comment_id
/// (refusal not yet committed to state + comments). Pure helper for tests + cleanup scan.
pub fn progress_shows_uncommitted_refusal(json: String) -> Bool {
  case ffi.parse(json) {
    Error(_) -> False
    Ok(root) -> {
      let status = progress_field_string(ffi.get_field(root, "status"))
      let decision = progress_field_string(ffi.get_field(root, "decision"))
      let comment_v =
        ffi.get_field_path(root, ["stages", "implement_or_refuse", "comment_id"])
      case progress_comment_id_present(comment_v) {
        True -> False
        False -> status == "refused" || decision == "refuse"
      }
    }
  }
}

fn progress_field_string(val: ffi.JsonValue) -> String {
  case ffi.decode_string(val) {
    Ok(s) -> s
    Error(_) -> ""
  }
}

fn progress_comment_id_present(val: ffi.JsonValue) -> Bool {
  case ffi.is_null(val) {
    True -> False
    False ->
      case ffi.decode_string(val) {
        Ok(s) -> s != ""
        Error(_) ->
          case ffi.decode_int(val) {
            Ok(_) -> True
            Error(_) -> False
          }
      }
  }
}

/// Task slugs whose worktrees must not be pruned (refusal.md and/or uncommitted refusal progress).
/// Committed refusals (progress has comment_id) are omitted so worktrees may be removed per spec/36.
pub fn collect_refusal_protected_tokens(tasks_dir: String) -> List(String) {
  case ffi.list_files(tasks_dir) {
    Error(_) -> []
    Ok(entries) ->
      list.filter_map(entries, fn(slug) {
        case string.starts_with(slug, ".") {
          True -> Error(Nil)
          False ->
            case task_needs_refusal_worktree_protection(tasks_dir, slug) {
              True -> Ok(slug)
              False -> Error(Nil)
            }
        }
      })
  }
}

fn task_needs_refusal_worktree_protection(tasks_dir: String, slug: String) -> Bool {
  let refusal_path = checkpoint.refusal_checkpoint_file(tasks_dir, slug)
  let progress_path = checkpoint.progress_file_for_task(tasks_dir, slug)
  let has_refusal_md = ffi.exists(refusal_path)
  case ffi.read_text(progress_path) {
    Error(_) -> has_refusal_md
    Ok(json) ->
      case progress_shows_uncommitted_refusal(json) {
        True -> True
        False -> False
      }
  }
}

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
