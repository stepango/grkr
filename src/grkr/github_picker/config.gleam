import gleam/int
import gleam/list
import gleam/string
import grkr/github_picker/ffi
import grkr/github_picker/types.{
  type ConfigError, type GitHubPickerConfig, type PriorityMode,
  GitHubPickerConfig, InvalidProjectNumber, MissingRequired,
}
import grkr/github_picker/priority

@external(javascript, "../github_picker/env.mjs", "getEnv")
fn get_env(name: String) -> String

@external(javascript, "../github_picker/file.mjs", "readFileSync")
fn read_file_sync(path: String) -> Result(String, String)

/// Default priority order (matches bash default)
pub const default_priority_order: List(String) = [
  "P0", "P1", "P2", "P3", "P4", "P5",
  "C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8",
]

/// Load GitHub picker config from environment variables (and optional .grkr files)
pub fn load() -> Result(GitHubPickerConfig, ConfigError) {
  case get_required("REPO") {
    Error(e) -> Error(e)
    Ok(repo) ->
      case get_required("PROJECT_OWNER") {
        Error(e) -> Error(e)
        Ok(project_owner) ->
          case get_required("PROJECT_NUMBER") {
            Error(e) -> Error(e)
            Ok(project_number_str) ->
              case int.parse(project_number_str) {
                Ok(n) if n > 0 -> {
                  let project_number = n

                  let status_field_name =
                    get_env_with_default("STATUS_FIELD_NAME", "Status")
                  let todo_value = get_env_with_default("TODO_VALUE", "Todo")
                  let priority_field_name =
                    get_env_with_default("PRIORITY_FIELD_NAME", "Priority")

                  let priority_mode_str = get_env("PRIORITY_MODE")
                  let priority_mode = priority.priority_mode_from_string(priority_mode_str)

                  let grkr_base =
                    get_env_with_default(
                      "GRKR_ROOT",
                      get_env_with_default("GRKR_GLEAM_PROJECT_ROOT", default_grkr_root()),
                    )
                  let grkr_dir = resolve_grkr_dir(grkr_base)
                  let priority_order_path =
                    get_env_with_default(
                      "GRKR_PRIORITY_ORDER_PATH",
                      grkr_dir <> "/priority_order.txt",
                    )
                  let priority_order = load_priority_order(priority_order_path)

                  let active_jobs_path =
                    get_env_with_default(
                      "GRKR_ACTIVE_JOBS_PATH",
                      grkr_dir <> "/state/active_jobs.json",
                    )
                  let active_jobs = load_active_jobs(active_jobs_path)

                  let bot_login = get_env_with_default("BOT_LOGIN", get_env("GITHUB_ACTOR"))

                  Ok(
                    GitHubPickerConfig(
                      repo: repo,
                      project_owner: project_owner,
                      project_number: project_number,
                      status_field_name: status_field_name,
                      todo_value: todo_value,
                      priority_field_name: priority_field_name,
                      priority_mode: priority_mode,
                      priority_order: priority_order,
                      active_jobs: active_jobs,
                      grkr_root: grkr_dir,
                      bot_login: bot_login,
                    ),
                  )
                }
                _ -> Error(InvalidProjectNumber(project_number_str))
              }
          }
      }
  }
}

fn get_required(name: String) -> Result(String, ConfigError) {
  let value = get_env(name)
  case value {
    v if v != "" -> Ok(v)
    _ -> Error(MissingRequired(name))
  }
}

fn get_env_with_default(name: String, default: String) -> String {
  let value = get_env(name)
  case value {
    v if v != "" -> v
    _ -> default
  }
}

fn default_grkr_root() -> String {
  // Fallback when GRKR_ROOT/GRKR_GLEAM_PROJECT_ROOT not set (tests or direct call)
  // In practice shell/doctor sets GRKR_ROOT before invoking the picker
  let home = get_env("HOME")
  case home {
    h if h != "" -> h <> "/.grkr"
    _ -> ".grkr"
  }
}

/// Resolve the .grkr directory from a base (project root or .grkr dir itself)
fn resolve_grkr_dir(base: String) -> String {
  let b = string.trim(base)
  case string.ends_with(b, ".grkr") || string.ends_with(b, "/.grkr") {
    True -> b
    False -> b <> "/.grkr"
  }
}

/// Load priority order list from file (one per line, ignore empty/comments)
/// Falls back to default_priority_order on error/missing
fn load_priority_order(path: String) -> List(String) {
  case read_file_sync(path) {
    Ok(content) -> {
      content
      |> string.split(on: "\n")
      |> list.map(string.trim)
      |> list.filter(fn(line) {
        line != "" && !string.starts_with(line, "#")
      })
      |> fn(lines) {
        case lines {
          [] -> default_priority_order
          _ -> lines
        }
      }
    }
    Error(_) -> default_priority_order
  }
}

/// Load list of active job keys (e.g. "issue:4:execution") from the JSON file.
/// Parses top-level object keys matching the pattern. Returns [] on missing or unreadable (non-fatal for picker)
fn load_active_jobs(path: String) -> List(String) {
  case read_file_sync(path) {
    Ok(content) ->
      case ffi.parse(content) {
        Ok(obj) ->
          case ffi.get_keys(obj) {
            Ok(keys) ->
              keys
              |> list.filter(fn(k) {
                string.starts_with(k, "issue:") && string.contains(k, ":execution")
              })
            Error(_) -> []
          }
        Error(_) -> []
      }
    Error(_) -> []
  }
}

/// For tests: construct a config directly
pub fn make_test_config(
  repo: String,
  project_owner: String,
  project_number: Int,
  todo_value: String,
  priority_mode: PriorityMode,
  priority_order: List(String),
  bot_login: String,
) -> GitHubPickerConfig {
  GitHubPickerConfig(
    repo: repo,
    project_owner: project_owner,
    project_number: project_number,
    status_field_name: "Status",
    todo_value: todo_value,
    priority_field_name: "Priority",
    priority_mode: priority_mode,
    priority_order: priority_order,
    active_jobs: [],
    grkr_root: ".grkr",
    bot_login: bot_login,
  )
}
