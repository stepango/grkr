//// phases.gleam
//// Phase dispatch, run_all_phases, and per-phase implementations (GitHub-only v2).
//// Per supervisor-design-final.md, spec/parts/09-main-loop-contract.md, 07-supervisor.md, 39-recommended-implementation-order.md (items 10-12), 14,15,36.
//// GitHub-only v2. Logging + escape duplicated (until logging.gleam).
//// Follows types, exact phase order/names from types + design, error boundaries.
//// run_pick uses direct github_picker/main.pick_next (no shell emit parse).
//// Implemented remaining: reap (recovery), cleanup (purge + wt count), scan_pr_conflicts (resolve_pr list + conflicted + !active), scan_comment_commands (lock + last_scan + schedule to full worker-handle-comment.sh per spec/15).
//// Scheduler now wired (t_58ea0e02); pick phase records+spawns; comment worker full (reactions, worktree, codex prompt+dispatch, reactions update, cleanup) landed in t_13a8a733; full Linear still later.
//// Lock acquire pattern fixed (t_17c4b022): Ok(Acquired) vs Ok(Busy)|Ok(LockError)|Error(_) in pick/scan_pr/scan_comment.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import grkr/github_picker/main as github_picker
import grkr/github_picker/types as picker_types
import grkr/resolve_pr/github as resolve_pr_github
import grkr/supervisor/ffi
import grkr/supervisor/lock
import grkr/supervisor/recovery
import grkr/supervisor/scheduler
import grkr/supervisor/state
import grkr/supervisor/types as t
import grkr/supervisor/worktree_cleanup
/// Run the fixed sequence of phases for one tick.
/// Never fails the supervisor (error boundaries inside); returns Ok(Nil) on completion.
/// Matches do_one_tick phase list + dispatch.
pub fn run_all_phases(config: t.SupervisorConfig, tick: Int) -> Result(Nil, t.SupervisorError) {
  let phases = [
    t.SyncMain,
    t.ScanPrConflicts,
    t.ScanCommentCommands,
    t.PickAndScheduleIssueExecution,
    t.ReapFinishedJobs,
    t.CleanupStaleWorktrees,
    // SleepUntilNextTick is implicit (sleep after tick in loop)
  ]

  list.each(phases, fn(phase) {
    let _ = run_phase(config, phase, tick)
    Nil
  })

  Ok(Nil)
}

/// Run one phase with test fail injection, started/completed logging, error boundary.
/// Returns PhaseResult; supervisor continues regardless of Failed.
fn run_phase(
  config: t.SupervisorConfig,
  phase: t.Phase,
  tick: Int,
) -> t.PhaseResult {
  let phase_str = t.phase_to_string(phase)
  let entity = "repo/" <> config.repo

  // Test hook: GRKR_FAIL_PHASES="pick_and_schedule_issue_execution,..."
  case list.contains(config.fail_phases, phase_str) {
    True -> {
      let err = t.PhaseFailed(phase_str, 99)
      let _ =
        log_error(
          config,
          phase_str,
          "-",
          entity,
          "test_fail_injected=true tick=" <> int.to_string(tick),
        )
      t.Failed(err)
    }
    False -> {
      let _ =
        log_info(
          config,
          phase_str,
          "-",
          entity,
          "phase_started=true tick=" <> int.to_string(tick),
        )

      let res = case phase {
        t.SyncMain -> run_sync_main_phase(config)
        t.PickAndScheduleIssueExecution -> run_pick_and_schedule_issue_execution_phase(config)
        t.ReapFinishedJobs -> run_reap_finished_jobs_phase(config)
        t.CleanupStaleWorktrees -> run_cleanup_stale_worktrees_phase(config)
        t.ScanPrConflicts -> run_scan_pr_conflicts_phase(config)
        t.ScanCommentCommands -> run_scan_comment_commands_phase(config)
        _ -> {
          let _ =
            log_info(
              config,
              phase_str,
              "-",
              entity,
              "stub=true msg=phase_logic_in_subsequent_cards",
            )
          t.Success
        }
      }

      let _ = case res {
        t.Success ->
          log_info(config, phase_str, "-", entity, "phase_completed=true")
        t.Skipped(reason) ->
          log_info(config, phase_str, "-", entity, "phase_skipped=" <> reason)
        t.Failed(e) ->
          log_error(
            config,
            phase_str,
            "-",
            entity,
            "phase_failed=" <> t.supervisor_error_to_string(e),
          )
      }

      res
    }
  }
}

// --- Per-phase implementations (GitHub-only v2; locks for phase serialization; sync delegates to worker; reap uses recovery; cleanup purges + stub prune; scans lock+log) ---

fn run_sync_main_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let worker = config.grkr_root <> "/bin/worker-sync-main.sh"
  case ffi.executable("bash", [worker], None) {
    ffi.ExecResult(0, _, _) -> {
      let _ =
        log_info(
          config,
          "sync_main",
          "-",
          entity,
          "worker_exit=0 git_sync_done=true",
        )
      t.Success
    }
    ffi.ExecResult(75, _, _) -> {
      let _ =
        log_info(
          config,
          "sync_main",
          "-",
          entity,
          "lock_busy=75 skipped=true",
        )
      t.Skipped("main_lock_busy")
    }
    ffi.ExecResult(code, _, stderr) -> {
      let _ =
        log_error(
          config,
          "sync_main",
          "-",
          entity,
          "worker_failed=true code="
            <> int.to_string(code)
            <> " stderr="
            <> escape_log_value(stderr),
        )
      t.Failed(t.PhaseFailed("sync_main", code))
    }
  }
}

fn run_pick_and_schedule_issue_execution_phase(
  config: t.SupervisorConfig,
) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let lpath = lock.lock_path(config.locks_dir, "issues")
  case lock.acquire_lock(lpath) {
    Ok(t.Acquired) -> {
      let _ = log_info(config, "pick", "-", entity, "lock_acquired=issues")

      // Direct Gleam call to github_picker (same process, no exec/emit parse).
      // pick_next() is pure, respects GITHUB_FIXTURE_PATH + active_jobs filter from env.
      // Minimal change; no dupe query (uses picker/client which wires query.gleam).
      let res = case github_picker.pick_next() {
        Ok(sel) -> {
          let _ =
            log_info(
              config,
              "pick",
              "-",
              entity,
              "selected=true issue_number="
                <> int.to_string(sel.issue_number)
                <> " job_key="
                <> sel.job_key
                <> " title="
                <> escape_log_value(sel.issue_title),
            )
          let proj_id = case sel.project_item_id {
            "" -> None
            p -> Some(p)
          }
          let _ = case scheduler.spawn_issue_execution(config, sel.issue_number, sel.task_slug, proj_id) {
            Ok(_pid) -> {
              log_info(
                config,
                "pick_and_schedule_issue_execution",
                sel.job_key,
                "issue/" <> int.to_string(sel.issue_number),
                "scheduled_jobs=1 selected_issue=" <> int.to_string(sel.issue_number) <> " task_slug=" <> sel.task_slug,
              )
              Nil
            }
            Error(e) -> {
              log_error(
                config,
                "pick_and_schedule_issue_execution",
                sel.job_key,
                "issue/" <> int.to_string(sel.issue_number),
                "spawn_failed=" <> t.supervisor_error_to_string(e),
              )
              Nil
            }
          }
          t.Success
        }
        Error(e) -> {
          case e {
            picker_types.Selection(picker_types.NoMatchingIssue) -> {
              let _ = log_info(config, "pick", "-", entity, "no_candidate=true")
              t.Skipped("no_matching_issue")
            }
            _ -> {
              let err_str = picker_types.provider_error_to_string(e)
              let _ =
                log_error(
                  config,
                  "pick",
                  "-",
                  entity,
                  "picker_error=" <> escape_log_value(err_str),
                )
              t.Failed(t.Other("github_picker:" <> err_str))
            }
          }
        }
      }
      let _ = lock.release_lock(lpath)
      res
    }
    Ok(t.Busy) | Ok(t.LockError(_)) | Error(_) -> {
      let _ = log_info(config, "pick", "-", entity, "issues_lock_busy=true")
      t.Skipped("issues_lock_busy")
    }
  }
}

fn run_reap_finished_jobs_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  case recovery.recover_dead_jobs(config, "reap_finished_jobs") {
    Ok(count) -> {
      let _ =
        log_info(
          config,
          "reap_finished_jobs",
          "-",
          entity,
          "dead_jobs_recovered=" <> int.to_string(count),
        )
      t.Success
    }
    Error(e) -> {
      let _ =
        log_error(
          config,
          "reap_finished_jobs",
          "-",
          entity,
          "recover_error=" <> t.supervisor_error_to_string(e),
        )
      t.Success
    }
  }
}

fn run_cleanup_stale_worktrees_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  // Purge stale job locks (complements startup; always safe)
  let _ = case recovery.purge_stale_lock_files(config) {
    Ok(purged) ->
      log_info(
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
  // actual TTL prune wired to live active_jobs (refusal dirs stub per prior task comment)
  let active_job_keys = case state.read_active_jobs(config.active_jobs_file) {
    Ok(jobs) -> dict.keys(jobs)
    Error(_) -> []
  }
  let refusal_dirs: List(String) = []  // refusal-protected checkpoint dirs from progress state (stub)
  let _ = case worktree_cleanup.prune_stale_worktrees(config, active_job_keys, refusal_dirs) {
    Ok(n) -> log_info(config, "cleanup_stale_worktrees", "-", entity, "pruned_worktrees=" <> int.to_string(n))
    Error(e) -> log_error(config, "cleanup_stale_worktrees", "-", entity, "prune_failed=" <> e)
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
    log_info(
      config,
      "cleanup_stale_worktrees",
      "-",
      entity,
      "worktree_count=" <> int.to_string(wt_count) <> " job_log_count=" <> int.to_string(log_count) <> " stale_locks_purged=done",
    )
  t.Success
}

fn run_scan_pr_conflicts_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let lpath = lock.lock_path(config.locks_dir, "prs")
  case lock.acquire_lock(lpath) {
    Ok(t.Acquired) -> {
      let _ = log_info(config, "scan_pr_conflicts", "-", entity, "lock_acquired=prs")

      // GitHub-only detection per spec/parts/14-phase-2 and 09-main-loop-contract
      // Uses resolve_pr/github (already implemented for worker-resolve-pr) to list + filter conflicted
      // Filters: open (from list), base==main, conflicted, and not already in active_jobs as pr:NNN:conflict-resolution
      let detection = case resolve_pr_github.list_open_prs() {
        Ok(prs) -> {
          case state.read_active_jobs(config.active_jobs_file) {
            Error(_) -> {
              let _ =
                log_error(
                  config,
                  "scan_pr_conflicts",
                  "-",
                  entity,
                  "active_jobs_read_failed_for_pr_scan=true using_empty",
                )
              let candidates =
                list.filter(prs, fn(pr) {
                  pr.base_ref == config.main_branch && pr.conflicted
                })
              let count = list.length(candidates)
              let _ =
                log_info(
                  config,
                  "scan_pr_conflicts",
                  "-",
                  entity,
                  "conflicts_found="
                    <> int.to_string(count)
                    <> " active_check_skipped=true scheduler_pending=true",
                )
              t.Success
            }
            Ok(jobs) -> {
              let candidates =
                list.filter(prs, fn(pr) {
                  pr.base_ref == config.main_branch && pr.conflicted
                })
              let new_conflicts =
                list.filter(candidates, fn(pr) {
                  let jk =
                    "pr:" <> int.to_string(pr.number) <> ":conflict-resolution"
                  !dict.has_key(jobs, jk)
                })
              let count = list.length(new_conflicts)
              let _ =
                log_info(
                  config,
                  "scan_pr_conflicts",
                  "-",
                  entity,
                  "conflicts_found="
                    <> int.to_string(count)
                    <> " scheduler_pending=true msg=would_schedule_resolve_pr_jobs",
                )
              t.Success
            }
          }
        }
        Error(e) -> {
          let _ =
            log_error(
              config,
              "scan_pr_conflicts",
              "-",
              entity,
              "list_open_prs_failed=" <> escape_log_value(e) <> " continuing",
            )
          t.Success
        }
      }
      let _ = lock.release_lock(lpath)
      detection
    }
    Ok(t.Busy) | Ok(t.LockError(_)) | Error(_) -> {
      let _ = log_info(config, "scan_pr_conflicts", "-", entity, "prs_lock_busy=true")
      t.Skipped("prs_lock_busy")
    }
  }
}

fn run_scan_comment_commands_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let lpath = lock.lock_path(config.locks_dir, "comments")
  case lock.acquire_lock(lpath) {
    Ok(t.Acquired) -> {
      let _ = log_info(config, "scan_comment_commands", "-", entity, "lock_acquired=comments")

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
        ts -> "last_scan=" <> escape_log_value(ts)
      }
      let _ = log_info(config, "scan_comment_commands", "-", entity, last_log <> " processed_state_present")

      let fetched = case fetch_recent_comments(config.repo, last_scan) {
        Ok(cs) -> cs
        Error(e) -> {
          let _ = log_error(config, "scan_comment_commands", "-", entity, "fetch_failed=" <> escape_log_value(e) <> " using_empty")
          []
        }
      }

      let actionable = list.filter(fetched, fn(c) {
        string.starts_with(string.trim(c.body), "@:robot:")
      })

      let processed = case state.read_processed_comments(config.processed_comments_file) {
        Ok(p) -> p
        Error(e) -> {
          let _ = log_error(config, "scan_comment_commands", "-", entity, "processed_read_failed=" <> escape_log_value(t.supervisor_error_to_string(e)) <> " using_empty")
          []
        }
      }

      let new_comments = list.filter(actionable, fn(c) { !list.contains(processed, c.id) })
      let new_count = list.length(new_comments)
      let _ = log_info(
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
              log_info(
                config,
                "scan_comment_commands",
                "comment:" <> c.id,
                "comment/" <> c.id,
                "scheduled=true pid=" <> int.to_string(pid) <> " body_preview=" <> escape_log_value(string.slice(c.body, 0, 60)),
              )
            Nil
          }
          Error(e) -> {
            let _ = log_error(config, "scan_comment_commands", "comment:" <> c.id, "comment/" <> c.id, "spawn_failed=" <> t.supervisor_error_to_string(e))
            Nil
          }
        }
      })

      // Mark + advance checkpoint (best effort, after schedule attempt)
      let _ = case state.mark_comments_processed(config.processed_comments_file, list.map(new_comments, fn(c) { c.id })) {
        Ok(_) -> log_info(config, "scan_comment_commands", "-", entity, "marked_processed=" <> int.to_string(new_count))
        Error(e) -> log_error(config, "scan_comment_commands", "-", entity, "mark_failed=" <> t.supervisor_error_to_string(e))
      }

      let now = ffi.utc_timestamp()
      let _ = case state.write_last_comment_scan(config.last_comment_scan_file, now) {
        Ok(_) -> log_info(config, "scan_comment_commands", "-", entity, "last_scan_updated=" <> escape_log_value(now))
        Error(e) -> log_error(config, "scan_comment_commands", "-", entity, "last_scan_write_failed=" <> t.supervisor_error_to_string(e))
      }

      let _ = lock.release_lock(lpath)
      t.Success
    }
    Ok(t.Busy) | Ok(t.LockError(_)) | Error(_) -> {
      let _ = log_info(config, "scan_comment_commands", "-", entity, "comments_lock_busy=true")
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

// --- Logging (duplicated from loop/recovery until logging.gleam extracted; matches shell) ---
fn escape_log_value(value: String) -> String {
  value
  |> string.replace("\n", " ")
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}

fn log_event(
  config: t.SupervisorConfig,
  level: String,
  phase: String,
  job_key: String,
  entity: String,
  message: String,
) -> Nil {
  let ts = ffi.utc_timestamp()
  let msg_esc = escape_log_value(message)
  let line =
    ts
    <> " "
    <> level
    <> " phase="
    <> phase
    <> " job="
    <> job_key
    <> " entity="
    <> entity
    <> " msg=\""
    <> msg_esc
    <> "\""

  let _ = ffi.append_log(config.main_log_file, line)
  let _ = ffi.append_log(config.loop_log_file, line)

  // per-job log if not -
  case job_key == "-" {
    True -> Nil
    False -> {
      let base = case t.job_key_from_string(job_key) {
        Ok(jk) -> t.job_key_log_basename(jk)
        Error(_) ->
          job_key
          |> string.replace(":", "-")
          |> string.replace("/", "-")
      }
      let jpath = config.job_logs_dir <> "/" <> base <> ".log"
      let _ = ffi.append_log(jpath, line)
      Nil
    }
  }
}

fn log_info(
  config: t.SupervisorConfig,
  phase: String,
  job: String,
  entity: String,
  msg: String,
) -> Nil {
  log_event(config, "INFO", phase, job, entity, msg)
}

fn log_error(
  config: t.SupervisorConfig,
  phase: String,
  job: String,
  entity: String,
  msg: String,
) -> Nil {
  log_event(config, "ERROR", phase, job, entity, msg)
}
