//// main.gleam
//// Entry point for Gleam supervisor (thin replacement for bin/robot-main.sh)
//// Usage: gleam run -m grkr/supervisor/main   (after env setup by doctor + config)
//// Test: GLEAM_ENV=test gleam run -m grkr/supervisor/main

import gleam/int
import gleam/io
import gleam/result
import grkr/supervisor/config
import grkr/supervisor/ffi
import grkr/supervisor/loop
import grkr/supervisor/types.{type SupervisorError}

pub fn main() -> Nil {
  case ffi.get_env("GLEAM_ENV") {
    "test" -> {
      io.println("[supervisor] GLEAM_ENV=test -> skipping real run (for unit tests)")
      Nil
    }
    _ -> {
      case run() {
        Ok(_) -> ffi.exit(0)
        Error(err) -> {
          io.println("supervisor fatal: " <> types.supervisor_error_to_string(err))
          ffi.exit(1)
        }
      }
    }
  }
}

/// Public run() for direct calls / tests (bypasses GLEAM_ENV check)
pub fn run() -> Result(Nil, SupervisorError) {
  use cfg <- result.try(config.load())

  let _ = config.ensure_layout(cfg)

  // initial log like shell (simple structured for now)
  let start_msg =
    "INFO phase=supervisor job=- entity=repo/"
    <> cfg.repo
    <> " msg=\"starting Gleam supervisor interval_secs="
    <> int.to_string(cfg.loop_interval_secs)
    <> "\""

  let _ = ffi.append_log(cfg.main_log_file, start_msg)

  io.println(
    "supervisor: starting (Gleam) interval="
    <> int.to_string(cfg.loop_interval_secs)
    <> "s repo="
    <> cfg.repo,
  )

  loop.run_loop(cfg)
}
