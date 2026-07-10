//// config.gleam
//// Load RefusalConfig from env (set by doctor.sh + .grkr/config.sh)
//// or test overrides. Mirrors supervisor/config.gleam pattern exactly for testability.

import gleam/int
import gleam/result
import gleam/string
import gleam/dict.{type Dict}
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

  let repo = case get("GITHUB_REPOSITORY", "") {
    "" -> get("REPO", "stepango/grkr")
    r -> r
  }
  let tasks_dir_raw = get("TASKS_DIR", ".grkr/tasks")
  let tasks_dir = resolve_tasks_dir(tasks_dir_raw, get("GRKR_ROOT", ""))
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
    get("PROJECT_NUMBER", "88")
    |> int.parse
    |> result.unwrap(88)
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

/// Absolute task dir under $GRKR_ROOT/.grkr/tasks when GRKR_ROOT is set (gleam runs from project root).
fn resolve_tasks_dir(raw: String, grkr_root: String) -> String {
  case string.starts_with(raw, "/") {
    True -> raw
    False -> {
      case string.trim(grkr_root) {
        "" -> raw
        root -> {
          let grkr_base = case string.ends_with(root, ".grkr") || string.ends_with(root, "/.grkr") {
            True -> root
            False -> root <> "/.grkr"
          }
          case raw {
            ".grkr/tasks" -> grkr_base <> "/tasks"
            _ -> {
              case string.starts_with(raw, ".grkr/") {
                True -> grkr_base <> "/" <> string.drop_start(raw, 6)
                False -> grkr_base <> "/" <> raw
              }
            }
          }
        }
      }
    }
  }
}

/// Keep for backward compat with existing callers (flow, tests); delegates to the new load()
pub fn load_runtime_config() -> Result(types.RefusalConfig, types.RefusalError) {
  load()
}