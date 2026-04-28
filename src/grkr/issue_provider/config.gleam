import gleam/int
import gleam/list
import gleam/result
import gleam/string
import grkr/issue_provider/types

/// Linear configuration loaded from environment and files
pub type LinearConfig {
  LinearConfig(
    credential_path: String,
    assignee_id: String,
    project_id: Result(String, Nil),
    team_id: Result(String, Nil),
    todo_state: String,
    priority_order: types.PriorityOrder,
  )
}

/// Load Linear configuration from environment variables
pub fn load_linear_config() -> Result(LinearConfig, types.ConfigError) {
  let credential_path = get_linear_credential_path()
  let assignee_id = get_required_env("LINEAR_ASSIGNEE_ID")
  let project_id = get_optional_env("LINEAR_PROJECT_ID")
  let team_id = get_optional_env("LINEAR_TEAM_ID")
  let todo_state = get_env_with_default("LINEAR_TODO_STATE", "Todo")

  case assignee_id {
    Ok(aid) -> {
      let priority_order = load_priority_order_from_env()

      Ok(LinearConfig(
        credential_path: credential_path,
        assignee_id: aid,
        project_id: project_id,
        team_id: team_id,
        todo_state: todo_state,
        priority_order: priority_order,
      ))
    }
    Error(err) -> Error(err)
  }
}

/// Load Linear configuration from a config file path
pub fn load_linear_config_from_file(
  path: String,
) -> Result(LinearConfig, types.ConfigError) {
  case read_file(path) {
    Ok(contents) -> parse_config_from_contents(contents)
    Error(_err) -> Error(types.InvalidCredentialFormat)
  }
}

/// Parse configuration from file contents
fn parse_config_from_contents(
  contents: String,
) -> Result(LinearConfig, types.ConfigError) {
  let lines = string.split(contents, "\n")

  let get_value = fn(key: String) -> Result(String, Nil) {
    let prefix = key <> "="
    let found =
      list.find(lines, fn(line) {
        string.starts_with(string.trim(line), prefix)
      })

    case found {
      Ok(line) -> {
        let trimmed = string.trim(line)
        let value =
          case string.length(trimmed) > string.length(prefix) {
            True -> {
              let _prefix_part = string.slice(trimmed, 0, string.length(prefix))
              string.slice(
                trimmed,
                string.length(prefix),
                string.length(trimmed),
              )
            }
            False -> ""
          }
          |> string.trim

        Ok(value)
      }
      Error(Nil) -> Error(Nil)
    }
  }

  let credential_path =
    get_value("LINEAR_CREDENTIAL_PATH")
    |> result.unwrap(get_linear_credential_path())

  let assignee_id = case get_value("LINEAR_ASSIGNEE_ID") {
    Ok(val) if val != "" -> Ok(val)
    _ -> Error(types.MissingCredentialPath)
  }

  let project_id = get_value("LINEAR_PROJECT_ID")
  let team_id = get_value("LINEAR_TEAM_ID")
  let todo_state =
    get_value("LINEAR_TODO_STATE")
    |> result.unwrap("Todo")

  case assignee_id {
    Ok(aid) -> {
      let priority_order = load_priority_order_from_config(lines)

      Ok(LinearConfig(
        credential_path: credential_path,
        assignee_id: aid,
        project_id: project_id,
        team_id: team_id,
        todo_state: todo_state,
        priority_order: priority_order,
      ))
    }
    Error(err) -> Error(err)
  }
}

/// Load priority order from environment variables
fn load_priority_order_from_env() -> types.PriorityOrder {
  let urgent =
    get_env_with_default("LINEAR_PRIORITY_URGENT", "0")
    |> parse_int
    |> result.unwrap(0)

  let high =
    get_env_with_default("LINEAR_PRIORITY_HIGH", "1")
    |> parse_int
    |> result.unwrap(1)

  let medium =
    get_env_with_default("LINEAR_PRIORITY_MEDIUM", "2")
    |> parse_int
    |> result.unwrap(2)

  let low =
    get_env_with_default("LINEAR_PRIORITY_LOW", "3")
    |> parse_int
    |> result.unwrap(3)

  let no_priority =
    get_env_with_default("LINEAR_PRIORITY_NONE", "4")
    |> parse_int
    |> result.unwrap(4)

  types.PriorityOrder(
    urgent: urgent,
    high: high,
    medium: medium,
    low: low,
    no_priority: no_priority,
  )
}

/// Load priority order from config lines
fn load_priority_order_from_config(lines: List(String)) -> types.PriorityOrder {
  let get_value = fn(key: String) -> String {
    let prefix = key <> "="
    let found =
      list.find(lines, fn(line) {
        string.starts_with(string.trim(line), prefix)
      })

    case found {
      Ok(line) -> {
        let trimmed = string.trim(line)
        case string.length(trimmed) > string.length(prefix) {
          True -> {
            let _prefix_part = string.slice(trimmed, 0, string.length(prefix))
            string.slice(trimmed, string.length(prefix), string.length(trimmed))
          }
          False -> ""
        }
        |> string.trim
      }
      Error(Nil) -> ""
    }
  }

  let urgent =
    get_value("LINEAR_PRIORITY_URGENT")
    |> parse_int
    |> result.unwrap(0)

  let high =
    get_value("LINEAR_PRIORITY_HIGH")
    |> parse_int
    |> result.unwrap(1)

  let medium =
    get_value("LINEAR_PRIORITY_MEDIUM")
    |> parse_int
    |> result.unwrap(2)

  let low =
    get_value("LINEAR_PRIORITY_LOW")
    |> parse_int
    |> result.unwrap(3)

  let no_priority =
    get_value("LINEAR_PRIORITY_NONE")
    |> parse_int
    |> result.unwrap(4)

  types.PriorityOrder(
    urgent: urgent,
    high: high,
    medium: medium,
    low: low,
    no_priority: no_priority,
  )
}

/// Get the default Linear credential path
fn get_linear_credential_path() -> String {
  let home = get_env_with_default("HOME", "")
  home <> "/.linear/secret.txt"
}

/// Get a required environment variable
fn get_required_env(name: String) -> Result(String, types.ConfigError) {
  let value = get_env(name)
  case value {
    v if v != "" -> Ok(v)
    _ -> Error(types.MissingCredentialPath)
  }
}

/// Get an optional environment variable
fn get_optional_env(name: String) -> Result(String, Nil) {
  let value = get_env(name)
  case value {
    v if v != "" -> Ok(v)
    _ -> Error(Nil)
  }
}

/// Get an environment variable with a default value
fn get_env_with_default(name: String, default: String) -> String {
  let value = get_env(name)
  case value {
    v if v != "" -> v
    _ -> default
  }
}

/// Parse a string to an integer
fn parse_int(s: String) -> Result(Int, Nil) {
  int.parse(s)
}

/// Create an issue filter from Linear config
pub fn config_to_filter(config: LinearConfig) -> types.IssueFilter {
  types.make_filter(
    config.todo_state,
    config.assignee_id,
    config.project_id,
    config.team_id,
  )
}

@external(javascript, "../issue_provider/env.mjs", "getEnv")
fn get_env(name: String) -> String

@external(javascript, "../issue_provider/file.mjs", "readFileSync")
fn read_file(path: String) -> Result(String, String)
