//// phases.gleam
//// Phase dispatch, run_all_phases, and per-phase implementations (stubs + github_picker wired pick).
//// Extracted from loop.gleam per supervisor-design-final.md (module 9).
//// GitHub-only v2 tiny slice. Logging + escape duplicated (until logging.gleam).
//// Follows types, exact phase order/names from types + design, error boundaries.
//// Stubs for sync_main (delegate via worker later), scans, schedule, reap, cleanup.
//// run_pick uses direct github_picker/main.pick_next (no shell emit parse).

import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import grkr/github_picker/main as github_picker
import grkr/github_picker/types as picker_types
import grkr/supervisor/ffi
import grkr/supervisor/lock
import grkr/supervisor/recovery
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

// --- Per-phase implementations (stubs or wired; keep <400 LOC total) ---

fn run_sync_main_phase(_config: t.SupervisorConfig) -> t.PhaseResult {
  // TODO (future card): delegate via ffi.executable("bash", [worker_path], ...) or direct
  // for now stub (sync_main/main already implemented separately; compat exec in sibling)
  t.Success
}

fn run_pick_and_schedule_issue_execution_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let _ = log_info(config, "pick", "-", entity, "phase_started=true")

  // Direct Gleam call to github_picker (same process, no exec/emit parse).
  // pick_next() is pure, respects GITHUB_FIXTURE_PATH + active_jobs filter from env.
  // Minimal change; no dupe query (uses picker/client which wires query.gleam).
  case github_picker.pick_next() {
    Ok(sel) -> {
      let _ =
        log_info(
          config,
          "pick",
          "-",
          entity,
          "selected=true issue_number=" <> int.to_string(sel.issue_number)
            <> " job_key=" <> sel.job_key
            <> " title=" <> escape_log_value(sel.issue_title),
        )
      // Schedule stub (per scope of this + sibling scheduler card): full record+spawn in scheduler.gleam
      let _ =
        log_info(
          config,
          "pick",
          "-",
          entity,
          "schedule_stub=true note=would_record_active_job_and_spawn_execution_workflow",
        )
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
}

fn run_reap_finished_jobs_phase(_config: t.SupervisorConfig) -> t.PhaseResult {
  // TODO: check pids in active_jobs via state + ffi.is_alive, remove dead, release locks
  // (recovery has recover_dead_jobs at startup; reap is per-tick complement)
  t.Success
}

fn run_cleanup_stale_worktrees_phase(_config: t.SupervisorConfig) -> t.PhaseResult {
  // TODO (per 36-cleanup-policy): every N ticks prune worktrees older than TTL,
  // also can call recovery.purge_stale_lock_files if needed here
  // Currently purge only at startup in loop/recovery
  t.Success
}

fn run_scan_pr_conflicts_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let _ =
    log_info(
      config,
      "scan_pr_conflicts",
      "-",
      entity,
      "stub=true msg=phase_logic_in_subsequent_cards",
    )
  t.Success
}

fn run_scan_comment_commands_phase(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let _ =
    log_info(
      config,
      "scan_comment_commands",
      "-",
      entity,
      "stub=true msg=phase_logic_in_subsequent_cards",
    )
  t.Success
}

// --- Logging (duplicated from loop/recovery until logging.gleam extracted; matches shell) --
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
