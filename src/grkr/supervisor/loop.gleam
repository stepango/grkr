//// loop.gleam
//// Main tick orchestration for the Gleam supervisor.
//// - recovery on startup
//// - tick loop with max_ticks support for tests
//// - delegates phase dispatch to phases.gleam (error boundaries, stubs + wired pick)
//// - GRKR_FAIL_PHASES injection for test error paths
//// - GitHub-only v2
//// - structured logging to main/loop/job logs (dupe helpers until logging.gleam)
//// Follows 09-main-loop-contract.md, 07-supervisor.md, shell robot-main.sh semantics.

import gleam/int
import gleam/option.{Some}
import gleam/string
import grkr/supervisor/ffi
import grkr/supervisor/phases
import grkr/supervisor/recovery
import grkr/supervisor/types as t

pub fn run_loop(config: t.SupervisorConfig) -> Result(Nil, t.SupervisorError) {
  let entity = "repo/" <> config.repo
  let _ = log_info(config, "startup", "-", entity, "gleam_supervisor_start=true version=gleam_v2")

  // Recovery first (matches shell before entering while loop)
  let _ = case recovery.recover_dead_jobs(config, "startup") {
    Ok(count) ->
      log_info(
        config,
        "startup",
        "-",
        entity,
        "recovered_dead_jobs=" <> int.to_string(count),
      )
    Error(e) ->
      log_error(
        config,
        "startup",
        "-",
        entity,
        "recover_failed=" <> t.supervisor_error_to_string(e),
      )
  }

  let _ = case recovery.purge_stale_lock_files(config) {
    Ok(count) ->
      log_info(
        config,
        "startup",
        "-",
        entity,
        "purged_stale_locks=" <> int.to_string(count),
      )
    Error(_) -> Nil
  }

  // Enter the main tick loop (tail recursive)
  run_tick_loop(config, 0)
}

fn run_tick_loop(
  config: t.SupervisorConfig,
  tick: Int,
) -> Result(Nil, t.SupervisorError) {
  // Test hook: GRKR_MAX_TICKS
  case config.max_ticks {
    Some(max) if tick >= max -> {
      let _ =
        log_info(
          config,
          "supervisor",
          "-",
          "repo/" <> config.repo,
          "max_ticks_reached="
            <> int.to_string(max)
            <> " exiting_for_test=true",
        )
      Ok(Nil)
    }
    _ -> {
      let _ = do_one_tick(config, tick)
      let _ = ffi.sleep_seconds(config.loop_interval_secs)
      run_tick_loop(config, tick + 1)
    }
  }
}

fn do_one_tick(config: t.SupervisorConfig, tick: Int) -> Nil {
  let entity = "repo/" <> config.repo
  let _ =
    log_info(
      config,
      "supervisor",
      "-",
      entity,
      "tick=" <> int.to_string(tick) <> " started=true",
    )

  let _ = phases.run_all_phases(config, tick)

  let _ =
    log_info(
      config,
      "supervisor",
      "-",
      entity,
      "tick=" <> int.to_string(tick) <> " completed=true",
    )
  Nil
}

// --- Logging (duplicated from recovery until logging.gleam extracted per design) ---

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
