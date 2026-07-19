//// phases_pick.gleam
//// PickAndScheduleIssueExecution phase (uses pick.pick_next + pick.schedule_selected).
//// Split out from phases.gleam for t_94976f9c LOC hygiene (thin dispatcher).
//// Calls existing grkr/supervisor/pick (do NOT duplicate); exact logs, lock paths,
//// skip reasons ("issues_lock_busy", "no_matching_issue"), schedule fields preserved.
/// Zero behavior change. Uses shared phases_log.
//// Per spec/parts/16 + 09 + 07.

import gleam/int
import gleam/option.{None, Some}

import grkr/supervisor/lock
import grkr/supervisor/phases_log as log
import grkr/supervisor/pick
import grkr/supervisor/types as t

pub fn run(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let lpath = lock.lock_path(config.locks_dir, "issues")
  case lock.acquire_lock(lpath) {
    Ok(t.Acquired) -> {
      let _ = log.log_info(config, "pick", "-", entity, "lock_acquired=issues")

      // Unified pick: github_picker or issue_provider per GRKR_ISSUE_PROVIDER (default github).
      let res = case pick.pick_next() {
        Ok(work) -> {
          let _ =
            log.log_info(
              config,
              "pick",
              "-",
              entity,
              "selected=true "
                <> pick.selected_log_fields(work)
                <> " title="
                <> log.escape_log_value(work.issue_title),
            )
          let scheduled = case pick.schedule_selected(config, work) {
            Ok(True) -> {
              let entity_id = case work.issue_number {
                Some(n) -> "issue/" <> int.to_string(n)
                None -> "linear/" <> {
                  case work.identifier {
                    Some(i) -> i
                    None -> "unknown"
                  }
                }
              }
              let _ =
                log.log_info(
                  config,
                  "pick_and_schedule_issue_execution",
                  work.job_key,
                  entity_id,
                  "scheduled_jobs=1 "
                    <> pick.schedule_success_log_fields(work),
                )
              True
            }
            Ok(False) -> {
              let _ =
                log.log_info(
                  config,
                  "pick_and_schedule_issue_execution",
                  work.job_key,
                  "linear/" <> {
                    case work.identifier {
                      Some(i) -> i
                      None -> "unknown"
                    }
                  },
                  "scheduled_jobs=0 schedule_pending=true "
                    <> pick.schedule_pending_log_fields(work),
                )
              False
            }
            Error(e) -> {
              let entity_id = case work.issue_number {
                Some(n) -> "issue/" <> int.to_string(n)
                None -> "linear/unknown"
              }
              let _ =
                log.log_error(
                  config,
                  "pick_and_schedule_issue_execution",
                  work.job_key,
                  entity_id,
                  "spawn_failed=" <> t.supervisor_error_to_string(e),
                )
              False
            }
          }
          let _ = scheduled
          t.Success
        }
        Error(e) -> {
          case e {
            pick.NoMatchingIssue -> {
              let _ = log.log_info(config, "pick", "-", entity, "no_candidate=true")
              t.Skipped("no_matching_issue")
            }
            pick.Failed(reason) -> {
              let _ =
                log.log_error(
                  config,
                  "pick",
                  "-",
                  entity,
                  "picker_error=" <> log.escape_log_value(reason),
                )
              t.Failed(t.Other("issue_picker:" <> reason))
            }
          }
        }
      }
      let _ = lock.release_lock(lpath)
      res
    }
    Ok(t.Busy) | Ok(t.LockError(_)) | Error(_) -> {
      let _ = log.log_info(config, "pick", "-", entity, "issues_lock_busy=true")
      t.Skipped("issues_lock_busy")
    }
  }
}
