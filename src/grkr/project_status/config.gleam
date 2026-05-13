import gleam/int
import gleam/string
import grkr/project_status/types.{
  type StatusConfig, type TargetStatus, Backlog, Custom, Done, InProgress,
  StatusConfig, Todo,
}

pub fn parse_updates_enabled(value: String) -> Bool {
  let lower = value |> string.trim |> string.lowercase
  case lower {
    "false" -> False
    "0" -> False
    "no" -> False
    "" -> True
    _ -> True
  }
}

pub fn target_status_value(
  status: TargetStatus,
  todo_value: String,
  in_progress_value: String,
  done_value: String,
  backlog_value: String,
) -> String {
  case status {
    Todo -> todo_value
    InProgress -> in_progress_value
    Done -> done_value
    Backlog -> backlog_value
    Custom(value) -> value
  }
}

pub fn config_from_env(
  env_getter: fn(String) -> String,
  _default_getter: fn() -> StatusConfig,
) -> Result(StatusConfig, String) {
  let project_owner =
    ensure_non_empty(env_getter("PROJECT_OWNER"), "PROJECT_OWNER")
  let project_number_str =
    ensure_non_empty(env_getter("PROJECT_NUMBER"), "PROJECT_NUMBER")

  case project_owner, project_number_str {
    Ok(owner), Ok(number_str) ->
      case int.parse(number_str) {
        Ok(number) ->
          Ok(StatusConfig(
            updates_enabled: parse_updates_enabled(env_getter(
              "ENABLE_PROJECT_STATUS_UPDATES",
            )),
            project_owner: owner,
            project_number: number,
            status_field_name: default_if_empty(
              env_getter("STATUS_FIELD_NAME"),
              "Status",
            ),
            todo_value: default_if_empty(env_getter("TODO_VALUE"), "Todo"),
            in_progress_value: default_if_empty(
              env_getter("IN_PROGRESS_VALUE"),
              "In Progress",
            ),
            done_value: default_if_empty(env_getter("DONE_VALUE"), "Done"),
            backlog_value: default_if_empty(
              env_getter("BACKLOG_VALUE"),
              "Backlog",
            ),
          ))
        Error(_) -> Error("Invalid PROJECT_NUMBER: " <> number_str)
      }
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
}

pub fn default_status_values() -> StatusConfig {
  StatusConfig(
    updates_enabled: True,
    project_owner: "",
    project_number: 1,
    status_field_name: "Status",
    todo_value: "Todo",
    in_progress_value: "In Progress",
    done_value: "Done",
    backlog_value: "Backlog",
  )
}

fn ensure_non_empty(value: String, name: String) -> Result(String, String) {
  case string.trim(value) {
    "" -> Error("Missing required env: " <> name)
    trimmed -> Ok(trimmed)
  }
}

fn default_if_empty(value: String, default_value: String) -> String {
  case string.trim(value) {
    "" -> default_value
    trimmed -> trimmed
  }
}
