//// phases.gleam
//// Phase dispatch, run_all_phases, and per-phase implementations (GitHub-only v2).
//// Per supervisor-design-final.md, spec/parts/09-main-loop-contract.md, 07-supervisor.md, 39-recommended-implementation-order.md (items 10-12), 14,15,36.
//// GitHub-only v2. Logging + escape duplicated (until logging.gleam).
//// Follows types, exact phase order/names from types + design, error boundaries.
//// run_pick uses direct github_picker/main.pick_next (no shell emit parse).
//// Implemented remaining: reap (recovery), cleanup (purge + wt count), scan_pr_conflicts (resolve_pr list + conflicted + !active), scan_comment_commands (lock + last_scan + stub schedule).
//// Scheduler now wired (t_58ea0e02); pick phase records+spawns; comment worker and full Linear still later.

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
    Ok(_) -> {
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
    Error(_) -> {
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
  // Worktree prune per spec/parts/36-cleanup-policy (every ~10 ticks, >1h TTL for done, etc.)
  // Tiny slice: list count (full mtime/TTL/active filter + rm in polish card)
  let wt_count = case ffi.list_files(config.worktrees_dir) {
    Ok(files) ->
      list.length(list.filter(files, fn(f) { !string.starts_with(f, ".") }))
    Error(_) -> 0
  }
  let _ =
    log_info(
      config,
      "cleanup_stale_worktrees",
      "-",
      entity,
      "worktree_prune=attempted count=" <> int.to_string(wt_count) <> " ttl_check=stub",
    )
  t.Success
}

fn run_scan_pr_conflicts_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let lpath = lock.lock_path(config.locks_dir, "prs")
  case lock.acquire_lock(lpath) {
    Ok(_) -> {
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
    Error(_) -> {
      let _ = log_info(config, "scan_pr_conflicts", "-", entity, "prs_lock_busy=true")
      t.Skipped("prs_lock_busy")
    }
  }
}

fn run_scan_comment_commands_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let lpath = lock.lock_path(config.locks_dir, "comments")
  case lock.acquire_lock(lpath) {
    Ok(_) -> {
      let _ = log_info(config, "scan_comment_commands", "-", entity, "lock_acquired=comments")

      // Structure per spec/parts/15, 09, 07; full discovery + last_scan/processed update + worker-handle
      // deferred to dedicated card (item 10 per 39-recommended). For now: read state files, log 0, keep resilient.
      let _ =
        case ffi.read_text(config.last_comment_scan_file) {
          Ok(ts) if ts != "" ->
            log_info(
              config,
              "scan_comment_commands",
              "-",
              entity,
              "last_scan=" <> escape_log_value(string.trim(ts)) <> " processed_state_present",
            )
          _ ->
            log_info(
              config,
              "scan_comment_commands",
              "-",
              entity,
              "last_scan=never comments_scanned=0 scheduler_pending=true msg=use_last_comment_scan_processed_in_later_card",
            )
        }
      // TODO later: gh api for recent comments containing @:robot: , filter new vs processed_comments.json, schedule Comment jobs
      let _ =
        log_info(
          config,
          "scan_comment_commands",
          "-",
          entity,
          "comments_scanned=0 scheduler_pending=true",
        )
      let _ = lock.release_lock(lpath)
      t.Success
    }
    Error(_) -> {
      let _ = log_info(config, "scan_comment_commands", "-", entity, "comments_lock_busy=true")
      t.Skipped("comments_lock_busy")
    }
  }
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
