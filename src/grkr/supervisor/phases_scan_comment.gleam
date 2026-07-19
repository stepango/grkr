//// phases_scan_comment.gleam
//// ScanCommentCommands phase + GitHub comment JSON helpers.
/// Split out from phases.gleam for t_94976f9c LOC hygiene (thin dispatcher).
//// Full impl per spec/parts/15-phase-3, 09, 07: lock, last_scan, gh api, @robot: filter,
//// dedup vs processed, schedule worker-handle-comment.sh via scheduler, mark + advance.
/// Helpers (fetch/parse/decode) stay here. Exact log strings, skip reasons, Success-on-error preserved.
/// Uses shared phases_log. Zero behavior change.
//// GitHub-only v2.

import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string

import grkr/supervisor/ffi
import grkr/supervisor/lock
import grkr/supervisor/phases_log as log
import grkr/supervisor/scheduler
import grkr/supervisor/state
import grkr/supervisor/types as t

pub fn run(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let lpath = lock.lock_path(config.locks_dir, "comments")
  case lock.acquire_lock(lpath) {
    Ok(t.Acquired) -> {
      let _ = log.log_info(config, "scan_comment_commands", "-", entity, "lock_acquired=comments")

      // Full impl per spec/parts/15-phase-3, 09-main-loop-contract, 07-supervisor, 39 item10 (GitHub-only v2)
      // Idempotent discovery of @:robot: comments via gh api /issues/comments?since= , filter vs processed_comments.json + last_scan
      // Schedule via scheduler (flock + record_active_job + job log), advance checkpoint.
      // Resilient: errors logged, lock released, always Success (or Skipped on busy). No supervisor crash.
      let last_scan = case state.read_last_comment_scan(config.last_comment_scan_file) {
        Ok(ts) if ts != "" ->
          ts
        _ ->
          ""
      }
      let last_log = case last_scan {
        "" -> "last_scan=never"
        ts -> "last_scan=" <> log.escape_log_value(ts)
      }
      let _ = log.log_info(config, "scan_comment_commands", "-", entity, last_log <> " processed_state_present")

      let fetched = case fetch_recent_comments(config.repo, last_scan) {
        Ok(cs) -> cs
        Error(e) -> {
          let _ = log.log_error(config, "scan_comment_commands", "-", entity, "fetch_failed=" <> log.escape_log_value(e) <> " using_empty")
          []
        }
      }

      let actionable = list.filter(fetched, fn(c) {
        string.starts_with(string.trim(c.body), "@:robot:")
      })

      let processed = case state.read_processed_comments(config.processed_comments_file) {
        Ok(p) -> p
        Error(e) -> {
          let _ = log.log_error(config, "scan_comment_commands", "-", entity, "processed_read_failed=" <> log.escape_log_value(t.supervisor_error_to_string(e)) <> " using_empty")
          []
        }
      }

      let new_comments = list.filter(actionable, fn(c) { !list.contains(processed, c.id) })
      let new_count = list.length(new_comments)
      let _ = log.log_info(
        config,
        "scan_comment_commands",
        "-",
        entity,
        "fetched=" <> int.to_string(list.length(fetched)) <>
          " actionable=" <> int.to_string(list.length(actionable)) <>
          " new=" <> int.to_string(new_count) <>
          " scheduler_pending=true",
      )

      // Schedule full worker-handle-comment.sh for each new (reactions + worktree + codex per spec/15; state already marked processed here for dedup).
      // Use let _ = list.each (not fold+discard) to explicitly discard Nil return and avoid any unused binding warning; side effects (spawn + per-comment logs) only.
      let _ = list.each(new_comments, fn(c) {
        let key = t.Comment(c.id)
        let task_slug = "comment-" <> c.id
        let worker_sh = config.grkr_root <> "/bin/worker-handle-comment.sh"
        let sj = scheduler.ScheduledJob(key, task_slug, None, [worker_sh, c.id])
        case scheduler.spawn_workflow(config, sj) {
          Ok(pid) -> {
            let _ =
              log.log_info(
                config,
                "scan_comment_commands",
                "comment:" <> c.id,
                "comment/" <> c.id,
                "scheduled=true pid=" <> int.to_string(pid) <> " body_preview=" <> log.escape_log_value(string.slice(c.body, 0, 60)),
              )
            Nil
          }
          Error(e) -> {
            let _ = log.log_error(config, "scan_comment_commands", "comment:" <> c.id, "comment/" <> c.id, "spawn_failed=" <> t.supervisor_error_to_string(e))
            Nil
          }
        }
      })

      // Mark + advance checkpoint (best effort, after schedule attempt)
      let _ = case state.mark_comments_processed(config.processed_comments_file, list.map(new_comments, fn(c) { c.id })) {
        Ok(_) -> log.log_info(config, "scan_comment_commands", "-", entity, "marked_processed=" <> int.to_string(new_count))
        Error(e) -> log.log_error(config, "scan_comment_commands", "-", entity, "mark_failed=" <> t.supervisor_error_to_string(e))
      }

      let now = ffi.utc_timestamp()
      let _ = case state.write_last_comment_scan(config.last_comment_scan_file, now) {
        Ok(_) -> log.log_info(config, "scan_comment_commands", "-", entity, "last_scan_updated=" <> log.escape_log_value(now))
        Error(e) -> log.log_error(config, "scan_comment_commands", "-", entity, "last_scan_write_failed=" <> t.supervisor_error_to_string(e))
      }

      let _ = lock.release_lock(lpath)
      t.Success
    }
    Ok(t.Busy) | Ok(t.LockError(_)) | Error(_) -> {
      let _ = log.log_info(config, "scan_comment_commands", "-", entity, "comments_lock_busy=true")
      t.Skipped("comments_lock_busy")
    }
  }
}

// --- Comment scan helpers (GitHub-only, gh api + manual decode via supervisor ffi; keep <1000 LOC total) ---
fn fetch_recent_comments(repo: String, since: String) -> Result(List(t.GitHubComment), String) {
  let path = case since {
    "" -> "repos/" <> repo <> "/issues/comments?per_page=100"
    _ -> "repos/" <> repo <> "/issues/comments?since=" <> since <> "&per_page=100"
  }
  let cmd = [
    "gh", "api", path,
    "--jq",
    "[.[] | {id: (.id | tostring), body: .body, created_at: .created_at, updated_at: .updated_at, user_login: .user.login, html_url: .html_url}]",
  ]
  case ffi.executable("gh", cmd, None) {
    ffi.ExecResult(0, stdout, _) -> parse_comment_list_json(stdout)
    ffi.ExecResult(code, _, stderr) ->
      Error("gh api exit=" <> int.to_string(code) <> " " <> string.trim(stderr))
  }
}

fn parse_comment_list_json(json: String) -> Result(List(t.GitHubComment), String) {
  let trimmed = string.trim(json)
  case trimmed {
    "" | "[]" | "null" -> Ok([])
    _ ->
      case ffi.parse(trimmed) {
        Error(e) -> Error("parse json: " <> e)
        Ok(root) ->
          case ffi.decode_array(root) {
            Error(e) -> Error("decode array: " <> e)
            Ok(items) -> list.try_map(items, decode_github_comment)
          }
      }
  }
}

fn decode_github_comment(item: ffi.JsonValue) -> Result(t.GitHubComment, String) {
  let id = case ffi.get_field(item, "id") |> ffi.decode_string {
    Ok(s) -> s
    _ ->
      case ffi.get_field(item, "id") |> ffi.decode_int {
        Ok(n) -> int.to_string(n)
        _ -> ""
      }
  }
  let body = case ffi.get_field(item, "body") |> ffi.decode_string {
    Ok(s) -> s
    _ -> ""
  }
  let created_at = case ffi.get_field(item, "created_at") |> ffi.decode_string {
    Ok(s) -> s
    _ -> ""
  }
  let updated_at = case ffi.get_field(item, "updated_at") |> ffi.decode_string {
    Ok(s) -> s
    _ -> ""
  }
  let user_login = case ffi.get_field(item, "user_login") |> ffi.decode_string {
    Ok(s) -> s
    _ -> ""
  }
  let html_url = case ffi.get_field(item, "html_url") |> ffi.decode_string {
    Ok(s) -> s
    _ -> ""
  }
  Ok(t.GitHubComment(id, body, created_at, updated_at, user_login, html_url))
}
