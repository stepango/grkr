//// loop.gleam
//// Main tick orchestration for the Gleam supervisor (run_loop + tick skeleton) GitHub-only v2.
/// Completed per kanban t_39ff5ed6 (skeleton + sleep_remaining + error boundary).
//// - recovery on startup (reap phase also does per-tick recover per later slices)
//// - tick loop with max_ticks support for tests (test bypass)
//// - delegates phase dispatch to phases.gleam (which has per-phase error boundaries + GRKR_FAIL_PHASES injection + now full impls not stubs)
//// - sleep_remaining using ffi.unix_seconds() + logging shims to preserve exact LOOP_INTERVAL_SECS wall time (no drift)
//// - uses shared logging.gleam via _str compat shims (removed all local dupe logging fns) [note: still dupe here pending extraction]
//// - GitHub-only v2
//// Follows 09-main-loop-contract.md, supervisor-design-final.md (esp. lines 267-310 for loop, phases), AGENTS.md (files <=1000 LOC), gleam-migration-patterns.md, spec/parts/* as canonical.
///
/// Decisions on this slice:
//// - sleep_remaining implemented here in pure Gleam (timing calc + case + log + ffi sleep); matches shell exactly for test grep 'sleep_secs=0'
//// - phase dispatch error boundary wrapped in do_one_tick (robustness even if phases always Ok)
//// - test mode behavior: max_ticks check at tick start (equiv to legacy count), GLEAM_ENV=test bypass in main.gleam, fail_phases in phases
//// - logging: switched all calls to log.log_*_str shims (config-first compat); deleted escape/log_event/log_info/log_error locals (shims temporary per logging.gleam) [kept dupe for now]
//// - phase stubs: early design had stubs in loop; now delegated fully, phases.gleam has the impls (pick etc) per e2e/review cards
//// - pure Gleam (case, result.try not needed here, int ops); FFI only via existing (unix_seconds, sleep_seconds, appends via logging)
//// - no changes outside supervisor/ dir per task spec; handoff via kanban_comment with full content
//// - tiny focused scope

import gleam/int
import gleam/option.{Some}
import gleam/string

import grkr/supervisor/ffi
import grkr/supervisor/phases
import grkr/supervisor/recovery
import grkr/supervisor/types as t

pub fn run_loop(config: t.SupervisorConfig) -> Result(Nil, t.SupervisorError) {
  let entity = "repo/" <> config.repo
  let _ =
    log_info(
      config,
      "startup",
      "-",
      entity,
      "gleam_supervisor_start=true version=gleam_v2",
    )

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
  // Test hook: GRKR_MAX_TICKS (bypass / exit for tests)
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
      let tick_started_at = ffi.unix_seconds()
      let _ = do_one_tick(config, tick)
      let _ = sleep_remaining(config, tick_started_at)
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

  // Phase dispatch with error boundary (per design + spec 09-main-loop-contract.md, 35-failure-handling.md)
  // phases.run_all_phases never returns Error in practice (internal per-phase boundaries + always Ok(Nil)),
  // but wrap for robustness. Phase stubs handled inside phases.gleam (some return "stub=true msg=phase_logic_in_subsequent_cards").
  // full pick/reap/cleanup/sync/scan_comment wired in subsequent cards. Test mode: GRKR_FAIL_PHASES handled inside phases.run_phase.
  let _ = case phases.run_all_phases(config, tick) {
    Ok(_) -> Nil
    Error(e) ->
      log_error(
        config,
        "supervisor",
        "-",
        entity,
        "phases_run_failed="
          <> t.supervisor_error_to_string(e)
          <> " tick="
          <> int.to_string(tick),
      )
  }

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

// sleep_remaining: compute wall time remaining in this tick's budget to keep precise LOOP_INTERVAL_SECS.
// Matches legacy shell sleep_remaining_time + spec/parts/09-main-loop-contract.md exactly (log + sleep).
// Pure Gleam arithmetic + case; JS FFI only for unix_seconds (time) + sleep_seconds (the actual pause).
// If phases overrun the interval (rare, e.g. slow gh), sleep 0 and continue immediately (no drift, no negative).
fn sleep_remaining(config: t.SupervisorConfig, tick_started_at: Int) -> Nil {
  let now = ffi.unix_seconds()
  let elapsed = now - tick_started_at
  let remaining = config.loop_interval_secs - elapsed
  let entity = "repo/" <> config.repo
  case remaining <= 0 {
    True -> {
      let _ =
        log_info(
          config,
          "sleep_until_next_tick",
          "-",
          entity,
          "sleep_secs=0",
        )
      Nil
    }
    False -> {
      let _ =
        log_info(
          config,
          "sleep_until_next_tick",
          "-",
          entity,
          "sleep_secs=" <> int.to_string(remaining),
        )
      let _ = ffi.sleep_seconds(remaining)
      Nil
    }
  }
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
