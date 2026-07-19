//// phases_scan_pr.gleam
//// ScanPrConflicts phase (GitHub-only detection via resolve_pr/github + active_jobs filter).
//// Split out from phases.gleam for t_94976f9c LOC hygiene (thin dispatcher).
//// Exact filter logic (base==main, conflicted, not already active as pr:NNN:...),
//// lock "prs", skip reason "prs_lock_busy", log fields preserved. Always Success on errors.
/// Uses shared phases_log. Zero behavior change.
//// Per spec/parts/14-phase-2-detect-and-resolve-pr-conflicts + 09-main-loop-contract.

import gleam/dict
import gleam/int
import gleam/list

import grkr/resolve_pr/github as resolve_pr_github
import grkr/supervisor/lock
import grkr/supervisor/phases_log as log
import grkr/supervisor/state
import grkr/supervisor/types as t

pub fn run(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let lpath = lock.lock_path(config.locks_dir, "prs")
  case lock.acquire_lock(lpath) {
    Ok(t.Acquired) -> {
      let _ = log.log_info(config, "scan_pr_conflicts", "-", entity, "lock_acquired=prs")

      // GitHub-only detection per spec/parts/14-phase-2 and 09-main-loop-contract
      // Uses resolve_pr/github (already implemented for worker-resolve-pr) to list + filter conflicted
      // Filters: open (from list), base==main, conflicted, and not already in active_jobs as pr:NNN:conflict-resolution
      let detection = case resolve_pr_github.list_open_prs() {
        Ok(prs) -> {
          case state.read_active_jobs(config.active_jobs_file) {
            Error(_) -> {
              let _ =
                log.log_error(
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
                log.log_info(
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
                log.log_info(
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
            log.log_error(
              config,
              "scan_pr_conflicts",
              "-",
              entity,
              "list_open_prs_failed=" <> log.escape_log_value(e) <> " continuing",
            )
          t.Success
        }
      }
      let _ = lock.release_lock(lpath)
      detection
    }
    Ok(t.Busy) | Ok(t.LockError(_)) | Error(_) -> {
      let _ = log.log_info(config, "scan_pr_conflicts", "-", entity, "prs_lock_busy=true")
      t.Skipped("prs_lock_busy")
    }
  }
}
