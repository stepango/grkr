//// phases_reap.gleam
//// ReapFinishedJobs phase (delegates to recovery.recover_*).
//// Split out from phases.gleam for t_94976f9c LOC hygiene (thin dispatcher).
//// Exact recovery calls, log fields, and "success even on error" semantics.
/// Uses shared phases_log. Zero behavior change.
//// Per spec/parts/36 + 09.

import gleam/int

import grkr/supervisor/phases_log as log
import grkr/supervisor/recovery
import grkr/supervisor/types as t

pub fn run(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let dead_result = recovery.recover_dead_jobs(config, "reap_finished_jobs")
  let stale_result = recovery.recover_stale_active_jobs(config, "reap_finished_jobs")

  case dead_result, stale_result {
    Ok(dead), Ok(stale) -> {
      let _ =
        log.log_info(
          config,
          "reap_finished_jobs",
          "-",
          entity,
          "dead_jobs_recovered="
            <> int.to_string(dead)
            <> " stale_ttl_jobs_recovered="
            <> int.to_string(stale),
        )
      t.Success
    }
    Error(e), _ | _, Error(e) -> {
      let _ =
        log.log_error(
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
