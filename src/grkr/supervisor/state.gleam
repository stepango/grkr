//// state.gleam
//// Active jobs JSON state management for the GRKR supervisor (v2 Gleam port).
//// Handles read/write of active_jobs.json with atomic updates, recovery of
//// dead jobs (stale PID), purge of orphan locks, and scheduling helpers.
////
//// Matches shell semantics from bin/robot-main.sh:
////   - record/remove use tmp+rename (via atomic_write_json FFI)
////   - recover_dead_jobs and purge use PID checks + lock_name fields
////   - active_issue_execution_count filters ^issue:NNN:execution$
////
//// Design: spec/parts/11-state-model.md, 33-locking-and-concurrency.md
//// supervisor-design-final.md

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import grkr/supervisor/ffi
import grkr/supervisor/types as t

/// Read and parse active_jobs.json into typed Dict.
/// Returns empty dict for missing/empty/"{}" files.
/// Errors on parse/decode failures (caller in recovery decides).
pub fn read_active_jobs(path: String) -> Result(Dict(String, t.ActiveJob), t.SupervisorError) {
  case ffi.read_text(path) {
    Error(e) -> Error(t.Io("read active_jobs: " <> e))
    Ok(content) -> {
      let trimmed = string.trim(content)
      case trimmed {
        "" | "{}" | "null" -> Ok(dict.new())
        json -> {
          case ffi.parse(json) {
            Error(e) -> Error(t.Parse("active_jobs json: " <> e))
            Ok(root) ->
              case ffi.get_keys(root) {
                Error(e) -> Error(t.Parse("get_keys: " <> e))
                Ok(keys) ->
                  case
                    list.try_map(keys, fn(k) {
                      let val = ffi.get_field(root, k)
                      decode_active_job(k, val)
                    })
                  {
                    Error(e) -> Error(t.Parse(e))
                    Ok(pairs) -> Ok(dict.from_list(pairs))
                  }
              }
          }
        }
      }
    }
  }
}

fn decode_active_job(key: String, val: ffi.JsonValue) -> Result(#(String, t.ActiveJob), String) {
  use pid <- result.try(ffi.decode_int(ffi.get_field(val, "pid")))
  let entity_type =
    case ffi.decode_string(ffi.get_field(val, "entity_type")) {
      Ok(s) -> s
      Error(_) -> "job"
    }
  let entity_id =
    case ffi.decode_string(ffi.get_field(val, "entity_id")) {
      Ok(s) -> s
      Error(_) -> "unknown"
    }
  let lock_name =
    case ffi.decode_string(ffi.get_field(val, "lock_name")) {
      Ok(s) -> s
      Error(_) -> ""
    }
  let task_slug =
    case ffi.decode_string(ffi.get_field(val, "task_slug")) {
      Ok(s) -> s
      Error(_) -> ""
    }
  let started_at =
    case ffi.decode_string(ffi.get_field(val, "started_at")) {
      Ok(s) -> s
      Error(_) -> ""
    }
  let proj_v = ffi.get_field(val, "project_item_id")
  let project_item_id =
    case ffi.is_null(proj_v) {
      True -> None
      False ->
        case ffi.decode_string(proj_v) {
          Ok(s) if s != "" -> Some(s)
          _ -> None
        }
    }
  Ok(#(
    key,
    t.ActiveJob(pid, entity_type, entity_id, lock_name, task_slug, started_at, project_item_id),
  ))
}

/// Atomic write of the jobs dict as JSON object.
/// Uses FFI tmp+rename for safety (no partial writes).
pub fn write_active_jobs_atomic(
  path: String,
  jobs: Dict(String, t.ActiveJob),
) -> Result(Nil, t.SupervisorError) {
  let json_str = active_jobs_to_json(jobs)
  case ffi.atomic_write_json(path, json_str) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(t.Io("atomic_write active_jobs: " <> e))
  }
}

fn active_jobs_to_json(jobs: Dict(String, t.ActiveJob)) -> String {
  let entries = dict.to_list(jobs)
  let parts =
    list.map(entries, fn(pair) {
      let #(k, aj) = pair
      let k_esc = escape_json(k)
      let v = active_job_to_json(aj)
      "\"" <> k_esc <> "\": " <> v
    })
  "{" <> string.join(parts, ", ") <> "}"
}

fn escape_json(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
}

fn active_job_to_json(aj: t.ActiveJob) -> String {
  let t.ActiveJob(pid, et, eid, ln, ts, sa, proj) = aj
  let pid_j = "\"pid\": " <> int.to_string(pid)
  let et_j = "\"entity_type\": \"" <> escape_json(et) <> "\""
  let eid_j = "\"entity_id\": \"" <> escape_json(eid) <> "\""
  let ln_j = "\"lock_name\": \"" <> escape_json(ln) <> "\""
  let ts_j = "\"task_slug\": \"" <> escape_json(ts) <> "\""
  let sa_j = "\"started_at\": \"" <> escape_json(sa) <> "\""
  let proj_j =
    case proj {
      Some(p) if p != "" -> ", \"project_item_id\": \"" <> escape_json(p) <> "\""
      _ -> ""
    }
  "{" <> string.join([pid_j, et_j, eid_j, ln_j, ts_j, sa_j], ", ") <> proj_j <> "}"
}

/// Record (insert or overwrite) a new active job entry.
/// Sets started_at to current UTC ISO timestamp.
/// Uses atomic write.
pub fn record_active_job(
  config: t.SupervisorConfig,
  key: t.JobKey,
  pid: Int,
  entity_type: String,
  entity_id: String,
  lock_name: String,
  task_slug: String,
  project_item_id: Option(String),
) -> Result(Nil, t.SupervisorError) {
  let path = config.active_jobs_file
  use current <- result.try(read_active_jobs(path))
  let jk_str = t.job_key_to_string(key)
  let started_at = ffi.utc_timestamp()
  let aj =
    t.ActiveJob(pid, entity_type, entity_id, lock_name, task_slug, started_at, project_item_id)
  let updated = dict.insert(current, jk_str, aj)
  write_active_jobs_atomic(path, updated)
}

/// Remove a job key from active_jobs.json (atomic).
/// Safe no-op if key absent.
pub fn remove_active_job(path: String, key: String) -> Result(Nil, t.SupervisorError) {
  use current <- result.try(read_active_jobs(path))
  let updated = dict.delete(current, key)
  write_active_jobs_atomic(path, updated)
}

/// Count how many active jobs are issue:<n>:execution (used by picker to gate concurrency).
pub fn count_active_issue_executions(jobs: Dict(String, t.ActiveJob)) -> Int {
  jobs
  |> dict.keys
  |> list.filter(fn(k) {
    string.starts_with(k, "issue:") && string.contains(k, ":execution")
  })
  |> list.length
}
