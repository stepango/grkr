//// phases_sync.gleam
//// SyncMain phase implementation (delegates to worker-sync-main.sh).
//// Split out from phases.gleam for t_94976f9c LOC hygiene (thin dispatcher).
//// Exact body/log/lock/exit semantics preserved; no behavior change.
/// Uses shared phases_log for identical log lines.
//// Per spec/parts/13 + 09-main-loop-contract.

import gleam/int
import gleam/option.{None}

import grkr/supervisor/ffi
import grkr/supervisor/phases_log as log
import grkr/supervisor/types as t

pub fn run(config: t.SupervisorConfig) -> t.PhaseResult {
  let entity = "repo/" <> config.repo
  let worker = config.grkr_root <> "/bin/worker-sync-main.sh"
  case ffi.executable("bash", [worker], None) {
    ffi.ExecResult(0, _, _) -> {
      let _ =
        log.log_info(
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
        log.log_info(
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
        log.log_error(
          config,
          "sync_main",
          "-",
          entity,
          "worker_failed=true code="
            <> int.to_string(code)
            <> " stderr="
            <> log.escape_log_value(stderr),
        )
      t.Failed(t.PhaseFailed("sync_main", code))
    }
  }
}
