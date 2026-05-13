import gleam/int
import gleam/io
import gleam/option
import grkr/project_status/config
import grkr/project_status/extraction
import grkr/project_status/normalization
import grkr/project_status/planning
import grkr/project_status/resolution
import grkr/project_status/types.{
  type MovePlan, type StatusConfig, type TargetStatus, AlreadyInStatus, Backlog,
  Custom, Disabled, Done, InProgress, ItemMissing, MoveAction, NoAction,
  OptionMissing, StatusConfig, Todo,
}

pub fn main() -> Nil {
  case argv() {
    ["check-enabled"] -> check_enabled(get_env("ENABLE_PROJECT_STATUS_UPDATES"))
    ["normalize", name] -> io.println(normalization.normalize_option_name(name))
    ["extract-item-id", issue_json, project_number] ->
      print_option(extraction.extract_item_id(
        issue_json,
        parse_optional_int(project_number),
      ))
    ["extract-status-name", issue_json, project_number] ->
      print_option(extraction.extract_status_name(
        issue_json,
        parse_optional_int(project_number),
      ))
    ["find-item-id", items_json, issue_number] ->
      find_item_id(items_json, issue_number)
    ["project-id", project_json] -> project_id(project_json)
    ["resolve-option", fields_json, field_name, option_name] ->
      resolve_option(fields_json, field_name, option_name)
    ["plan-move", issue_json, project_json, fields_json, target_status] ->
      plan_move(issue_json, project_json, fields_json, target_status)
    _ -> {
      io.println(
        "Usage: gleam run -m grkr/project_status_cli -- <subcommand> ...",
      )
      exit(2)
    }
  }
}

fn check_enabled(raw: String) -> Nil {
  case config.parse_updates_enabled(raw) {
    True -> io.println("enabled")
    False -> io.println("disabled")
  }
}

fn print_option(value: option.Option(String)) -> Nil {
  case value {
    option.Some(text) -> io.println(text)
    option.None -> io.println("")
  }
}

fn find_item_id(items_json: String, issue_number: String) -> Nil {
  case int.parse(issue_number) {
    Ok(number) ->
      print_option(extraction.find_item_id_by_issue_number(items_json, number))
    Error(_) -> io.println("")
  }
}

fn project_id(project_json: String) -> Nil {
  case extraction.extract_project_metadata(project_json) {
    Ok(metadata) -> io.println(metadata.id)
    Error(_) -> io.println("")
  }
}

fn resolve_option(
  fields_json: String,
  field_name: String,
  option_name: String,
) -> Nil {
  case resolution.parse_project_fields(fields_json) {
    Ok(fields) ->
      case
        resolution.find_field_and_option_ids(fields, field_name, option_name)
      {
        Ok(#(field_id, option_id, _resolved_name)) ->
          io.println(field_id <> "\t" <> option_id)
        Error(_) -> io.println("")
      }
    Error(_) -> io.println("")
  }
}

fn plan_move(
  issue_json: String,
  project_json: String,
  fields_json: String,
  target_status: String,
) -> Nil {
  case project_config() {
    Error(_) -> io.println("no_action\tresolution_failed")
    Ok(status_config) ->
      case status_config.updates_enabled {
        False -> io.println("no_action\tdisabled")
        True ->
          case extraction.extract_project_metadata(project_json) {
            Error(_) -> io.println("no_action\tresolution_failed")
            Ok(metadata) ->
              case resolution.parse_project_fields(fields_json) {
                Error(_) -> io.println("no_action\tresolution_failed")
                Ok(fields) -> {
                  let target = parse_target_status(target_status, status_config)
                  planning.plan_status_update(
                    status_config,
                    metadata,
                    fields,
                    issue_json,
                    target,
                  )
                  |> output_move_plan
                }
              }
          }
      }
  }
}

fn project_config() -> Result(StatusConfig, String) {
  let owner = default_if_empty(get_env("PROJECT_OWNER"), "")
  let number = default_if_empty(get_env("PROJECT_NUMBER"), "1")
  case int.parse(number) {
    Error(_) -> Error("bad project number")
    Ok(project_number) ->
      Ok(StatusConfig(
        updates_enabled: config.parse_updates_enabled(get_env(
          "ENABLE_PROJECT_STATUS_UPDATES",
        )),
        project_owner: owner,
        project_number: project_number,
        status_field_name: default_if_empty(
          get_env("STATUS_FIELD_NAME"),
          "Status",
        ),
        todo_value: default_if_empty(get_env("TODO_VALUE"), "Todo"),
        in_progress_value: default_if_empty(
          get_env("IN_PROGRESS_VALUE"),
          "In Progress",
        ),
        done_value: default_if_empty(get_env("DONE_VALUE"), "Done"),
        backlog_value: default_if_empty(get_env("BACKLOG_VALUE"), "Backlog"),
      ))
  }
}

fn parse_target_status(
  status: String,
  status_config: StatusConfig,
) -> TargetStatus {
  let normalized = normalization.normalize_option_name(status)
  case
    normalized == normalization.normalize_option_name(status_config.todo_value)
  {
    True -> Todo
    False ->
      case
        normalized
        == normalization.normalize_option_name(status_config.in_progress_value)
      {
        True -> InProgress
        False ->
          case
            normalized
            == normalization.normalize_option_name(status_config.done_value)
          {
            True -> Done
            False ->
              case
                normalized
                == normalization.normalize_option_name(
                  status_config.backlog_value,
                )
              {
                True -> Backlog
                False -> Custom(status)
              }
          }
      }
  }
}

fn output_move_plan(plan: MovePlan) -> Nil {
  case plan {
    MoveAction(item_id, field_id, option_id, option_name, project_id) ->
      io.println(
        "move\t"
        <> item_id
        <> "\t"
        <> field_id
        <> "\t"
        <> option_id
        <> "\t"
        <> project_id
        <> "\t"
        <> option_name,
      )
    NoAction(reason) ->
      case reason {
        Disabled -> io.println("no_action\tdisabled")
        ItemMissing -> io.println("no_action\titem_missing")
        AlreadyInStatus(_) -> io.println("no_action\talready")
        OptionMissing -> io.println("no_action\tresolution_failed")
        _ -> io.println("no_action\tresolution_failed")
      }
  }
}

fn parse_optional_int(value: String) -> option.Option(Int) {
  case value {
    "" -> option.None
    _ ->
      case int.parse(value) {
        Ok(number) -> option.Some(number)
        Error(_) -> option.None
      }
  }
}

fn default_if_empty(value: String, default_value: String) -> String {
  case value {
    "" -> default_value
    _ -> value
  }
}

@external(javascript, "./project_status_cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "./project_status_cli_ffi.mjs", "getEnv")
fn get_env(name: String) -> String

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil
