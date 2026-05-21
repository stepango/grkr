import gleam/option.{type Option, None, Some}
import gleam/int
import grkr/refusal/types.{type RefusalConfig, type RefusalError, RefusalConfig}

@external(javascript, "../refusal/env.mjs", "get_env")
pub fn get_env(name: String) -> String

@external(javascript, "../refusal/env.mjs", "get_env_with_default")
pub fn get_env_with_default(name: String, default: String) -> String

@external(javascript, "../refusal/env.mjs", "has_env")
pub fn has_env(name: String) -> Bool

/// Load runtime config from env, with sensible defaults for GitHub-only refusal flow
pub fn load_runtime_config() -> Result(RefusalConfig, RefusalError) {
  let repo = get_env_with_default("GITHUB_REPOSITORY", "stepango/grkr")
  let tasks_dir = get_env_with_default("TASKS_DIR", ".grkr/tasks")
  let updates_enabled = case get_env("ENABLE_PROJECT_STATUS_UPDATES") {
    "false" | "0" | "no" -> False
    _ -> True
  }
  let requires_backlog = case get_env("REFUSAL_REQUIRES_BACKLOG_MOVE") {
    "false" | "0" | "no" -> False
    _ -> True
  }
  let backlog_value = get_env_with_default("BACKLOG_VALUE", "Backlog")
  let project_number = case int_from_env("PROJECT_NUMBER") {
    Some(n) -> n
    None -> 88  // default from common usage
  }
  let project_owner = get_env_with_default("PROJECT_OWNER", "stepango")
  let status_field_name = get_env_with_default("STATUS_FIELD_NAME", "Status")

  Ok(RefusalConfig(
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

fn int_from_env(name: String) -> Option(Int) {
  let v = get_env(name)
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
