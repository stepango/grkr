//// config.gleam
//// Load RefusalConfig from env (set by doctor.sh + .grkr/config.sh)
//// or test overrides. Mirrors supervisor/config.gleam pattern exactly for testability.

import gleam/dict.{type Dict}
import gleam/int
import gleam/option.{type Option, None, Some}
import grkr/refusal/ffi
import grkr/refusal/types as types

pub fn load() -> Result(types.RefusalConfig, types.RefusalError) {
  load_with_overrides(dict.new())
}

/// For tests: provide env overrides (e.g. for PROJECT_NUMBER, *_VALUE, ENABLE_* flags, dirs)
pub fn load_for_test(overrides: Dict(String, String)) -> Result(types.RefusalConfig, types.RefusalError) {
  load_with_overrides(overrides)
}

fn load_with_overrides(overrides: Dict(String, String)) -> Result(types.RefusalConfig, types.RefusalError) {
  let get = fn(key: String, default: String) {
    case dict.get(overrides, key) {
      Ok(v) -> v
      Error(_) -> ffi.get_env_with_default(key, default)
    }
  }

  let repo = get("GITHUB_REPOSITORY", "stepango/grkr")
  let tasks_dir = get("TASKS_DIR", ".grkr/tasks")
  let updates_enabled = case get("ENABLE_PROJECT_STATUS_UPDATES", "") {
    "false" | "0" | "no" -> False
    _ -> True
  }
  let requires_backlog = case get("REFUSAL_REQUIRES_BACKLOG_MOVE", "") {
    "false" | "0" | "no" -> False
    _ -> True
  }
  let backlog_value = get("BACKLOG_VALUE", "Backlog")
  let project_number =
    case int_from_env("PROJECT_NUMBER", overrides) {
      Some(n) -> n
      None -> 88  // default from common usage
    }
  let project_owner = get("PROJECT_OWNER", "stepango")
  let status_field_name = get("STATUS_FIELD_NAME", "Status")

  Ok(types.RefusalConfig(
    repo: repo,
    tasks_dir: tasks_dir,
    updates_enabled: updates_enabled,
    requires_backlog: requires_backlog,
    backlog_value: backlog_value,
    project_number: project_number,
    project_owner: project_owner,
    status_field_name: status_field_name,
  ))
}

fn int_from_env(name: String, overrides: Dict(String, String)) -> Option(Int) {
  let v = case dict.get(overrides, name) {
    Ok(v) -> v
    Error(_) -> ffi.get_env(name)
  }
  case v {
    "" -> None
    s -> {
      case int.parse(s) {
        Ok(n) -> Some(n)
        Error(_) -> None
      }
    }
  }
}

/// Keep for backward compat with existing callers (flow, tests); delegates to the new load()
pub fn load_runtime_config() -> Result(types.RefusalConfig, types.RefusalError) {
  load()
}
