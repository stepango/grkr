//// phases.gleam
//// Thin dispatcher for supervisor phases (t_94976f9c LOC hygiene split).
//// Delegates to concern modules: phases_sync, phases_pick, phases_reap,
//// phases_cleanup, phases_scan_pr, phases_scan_comment.
/// run_all_phases + run_phase (fail injection + started/completed/skipped/failed logs + dispatch).
//// Exact original phase order, PhaseResult, GRKR_FAIL_PHASES, log field strings preserved.
/// Imports only what dispatcher needs; no impl bodies remain here.
/// Used exclusively by loop.gleam via phases.run_all_phases.
//// Zero intentional behavior change. All files <<1000 LOC.

import gleam/int
import gleam/list

import grkr/supervisor/phases_cleanup
import grkr/supervisor/phases_log as log
import grkr/supervisor/phases_pick
import grkr/supervisor/phases_reap
import grkr/supervisor/phases_scan_comment
import grkr/supervisor/phases_scan_pr
import grkr/supervisor/phases_sync
import grkr/supervisor/types as t

/// Run the fixed sequence of phases for one tick.
/// Never fails the supervisor (error boundaries inside); returns Ok(Nil) on completion.
/// Matches do_one_tick phase list + dispatch. Phase order is canonical.
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
      let err = t.PhaseFailed(phase_str, 64)
      let _ =
        log.log_error(
          config,
          phase_str,
          "-",
          entity,
          "phase_failed=" <> t.supervisor_error_to_string(err),
        )
      t.Failed(err)
    }
    False -> {
      let _ =
        log.log_info(
          config,
          phase_str,
          "-",
          entity,
          "phase_started=true tick=" <> int.to_string(tick),
        )

      let res = case phase {
        t.SyncMain -> phases_sync.run(config)
        t.ScanPrConflicts -> phases_scan_pr.run(config)
        t.ScanCommentCommands -> phases_scan_comment.run(config)
        t.PickAndScheduleIssueExecution -> phases_pick.run(config)
        t.ReapFinishedJobs -> phases_reap.run(config)
        t.CleanupStaleWorktrees -> phases_cleanup.run(config)
        _ -> {
          let _ =
            log.log_info(
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
          log.log_info(config, phase_str, "-", entity, "phase_completed=true")
        t.Skipped(reason) ->
          log.log_info(config, phase_str, "-", entity, "phase_skipped=" <> reason)
        t.Failed(e) ->
          log.log_error(
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
