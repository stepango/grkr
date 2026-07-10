//// scheduler.gleam
//// Background workflow spawner + active job recorder for supervisor pick phase etc.
//// Replicates shell `schedule_issue_execution_job` exactly (flock wrapper, pid capture, record, logs via caller).
//// Types: ScheduledJob + spawn_workflow / spawn_issue_execution helpers.
//// GitHub-only v2. Uses state.record_active_job (atomic), ffi.spawn_detached + exists.
//// Per supervisor-design-final.md, spec/parts/07/09/39, AGENTS.md (file <1000 LOC).

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

import grkr/supervisor/ffi
import grkr/supervisor/state
import grkr/supervisor/types as t

/// Scheduled job descriptor (for pick_and_schedule and future phases).
pub type ScheduledJob {
  ScheduledJob(
    key: t.JobKey,
    task_slug: String,
    project_item_id: Option(String),
    worker_cmd: List(String),
  )
}

/// Resolve the grkr binary path for this run (test vs real layout).
/// Prefers $GRKR_ROOT/grkr (test mocks place it at root), falls back to bin/grkr.
fn resolve_grkr_bin(config: t.SupervisorConfig) -> String {
  let c1 = config.grkr_root <> "/grkr"
  case ffi.exists(c1) {
    True -> c1
    False -> config.grkr_root <> "/bin/grkr"
  }
}

/// Spawn a background workflow under its per-job flock lock (exact shell semantics).
/// Builds bash -c '(flock -n 9 || exit 75; <cmd...>) 9>lock >>joblog 2>&1'
/// Captures launcher pid, records via state (atomic json), returns pid.
pub fn spawn_workflow(
  config: t.SupervisorConfig,
  sj: ScheduledJob,
) -> Result(Int, t.SupervisorError) {
  let ScheduledJob(key, task_slug, project_item_id, worker_cmd) = sj
  let jk_str = t.job_key_to_string(key)
  let lock_name = t.job_key_lock_name(key)
  let lock_file = config.locks_dir <> "/" <> lock_name <> ".lock"
  let base = t.job_key_log_basename(key)
  let job_log = config.job_logs_dir <> "/" <> base <> ".log"

  let _ = ffi.mkdir_p(config.locks_dir)
  let _ = ffi.mkdir_p(config.job_logs_dir)
  let _ = ffi.write_text(job_log, "")

  let inner_cmd = build_cmd_string(worker_cmd)
  let wrapper =
    "( flock -n 9 || exit 75 ; "
    <> inner_cmd
    <> " ) 9>"
    <> shell_quote(lock_file)
    <> " >>"
    <> shell_quote(job_log)
    <> " 2>&1"

  let pid = ffi.spawn_detached("bash", ["-c", wrapper], dict.new())
  case pid {
    0 -> Error(t.SpawnFailed("bash wrapper for " <> jk_str))
    p -> {
      let #(etype, eid) = entity_from_key(key)
      case
        state.record_active_job(
          config,
          key,
          p,
          etype,
          eid,
          lock_name,
          task_slug,
          project_item_id,
        )
      {
        Ok(_) -> Ok(p)
        Error(e) -> Error(e)
      }
    }
  }
}

/// Convenience for the current GitHub pick phase (issue:NNN:execution workflow).
pub fn spawn_issue_execution(
  config: t.SupervisorConfig,
  issue_number: Int,
  task_slug: String,
  project_item_id: Option(String),
) -> Result(Int, t.SupervisorError) {
  let key = t.IssueExecution(issue_number)
  let grkr_bin = resolve_grkr_bin(config)
  let worker_cmd = [grkr_bin, "--issue", int.to_string(issue_number)]
  let sj = ScheduledJob(key, task_slug, project_item_id, worker_cmd)
  spawn_workflow(config, sj)
}

fn entity_from_key(key: t.JobKey) -> #(String, String) {
  case key {
    t.IssueExecution(n) -> #("issue", int.to_string(n))
    t.PrConflict(n) -> #("pr", int.to_string(n))
    t.Comment(id) -> #("comment", id)
  }
}

fn build_cmd_string(cmd: List(String)) -> String {
  case cmd {
    [] -> ""
    [first, ..rest] -> {
      let qfirst = shell_quote(first)
      list.fold(rest, qfirst, fn(acc, arg) { acc <> " " <> shell_quote(arg) })
    }
  }
}

fn shell_quote(value: String) -> String {
  "\""
  <> value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("$", "\\$")
    |> string.replace("`", "\\`")
  <> "\""
}
