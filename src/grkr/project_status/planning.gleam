import gleam/int
import gleam/option
import gleam/result
import grkr/project_status/config.{target_status_value}
import grkr/project_status/extraction
import grkr/project_status/normalization
import grkr/project_status/resolution
import grkr/project_status/types.{
  type MovePlan, type ProjectMetadata, type StatusConfig, type StatusField,
  type TargetStatus, AlreadyInStatus, Backlog, Disabled, Done, FieldMissing,
  InProgress, ItemMissing, MoveAction, NoAction, OptionMissing, Todo,
}

/// Plan a status update for an issue
pub fn plan_status_update(
  config: StatusConfig,
  project_metadata: ProjectMetadata,
  status_fields: List(StatusField),
  issue_json: String,
  target_status: TargetStatus,
) -> MovePlan {
  // Check if updates are enabled
  case config.updates_enabled {
    False -> NoAction(Disabled)
    _ -> {
      // Extract item ID from issue JSON
      let project_number = option.Some(config.project_number)
      let item_id = extraction.extract_item_id(issue_json, project_number)

      case item_id {
        option.None -> NoAction(ItemMissing)
        option.Some(id) -> {
          // Check current status
          let current_status =
            extraction.extract_status_name(issue_json, project_number)

          let target_name =
            target_status_value(
              target_status,
              config.todo_value,
              config.in_progress_value,
              config.done_value,
              config.backlog_value,
            )

          case current_status {
            option.Some(current) -> {
              case normalization.names_match(current, target_name) {
                True -> {
                  NoAction(AlreadyInStatus(current))
                }
                _ -> {
                  // Resolve field and option IDs
                  case
                    resolution.find_field_and_option_ids(
                      status_fields,
                      config.status_field_name,
                      target_name,
                    )
                  {
                    Ok(#(field_id, option_id, _opt_name)) -> {
                      MoveAction(
                        item_id: id,
                        field_id: field_id,
                        option_id: option_id,
                        option_name: target_name,
                        project_id: project_metadata.id,
                      )
                    }
                    _ -> NoAction(OptionMissing)
                  }
                }
              }
            }
            option.None -> {
              // Resolve field and option IDs
              case
                resolution.find_field_and_option_ids(
                  status_fields,
                  config.status_field_name,
                  target_name,
                )
              {
                Ok(#(field_id, option_id, _opt_name)) -> {
                  MoveAction(
                    item_id: id,
                    field_id: field_id,
                    option_id: option_id,
                    option_name: target_name,
                    project_id: project_metadata.id,
                  )
                }
                _ -> NoAction(OptionMissing)
              }
            }
          }
        }
      }
    }
  }
}

/// Plan a status update with direct item lookup (fallback when item not in issue JSON)
pub fn plan_status_update_with_item_lookup(
  config: StatusConfig,
  project_metadata: ProjectMetadata,
  status_fields: List(StatusField),
  issue_json: String,
  items_json: String,
  target_status: TargetStatus,
) -> MovePlan {
  case config.updates_enabled {
    False -> NoAction(Disabled)
    _ -> {
      let issue_number =
        extraction.extract_issue_number(issue_json)
        |> result.unwrap(-1)

      let project_number = option.Some(config.project_number)
      let item_id = extraction.extract_item_id(issue_json, project_number)

      let final_item_id = case item_id {
        option.None ->
          extraction.find_item_id_by_issue_number(items_json, issue_number)
        _ -> item_id
      }

      case final_item_id {
        option.None -> NoAction(ItemMissing)
        option.Some(id) -> {
          let current_status =
            extraction.extract_status_name(issue_json, project_number)

          let target_name =
            target_status_value(
              target_status,
              config.todo_value,
              config.in_progress_value,
              config.done_value,
              config.backlog_value,
            )

          case current_status {
            option.Some(current) -> {
              case normalization.names_match(current, target_name) {
                True -> {
                  NoAction(AlreadyInStatus(current))
                }
                _ -> {
                  case
                    resolution.find_field_and_option_ids(
                      status_fields,
                      config.status_field_name,
                      target_name,
                    )
                  {
                    Ok(#(field_id, option_id, _opt_name)) -> {
                      MoveAction(
                        item_id: id,
                        field_id: field_id,
                        option_id: option_id,
                        option_name: target_name,
                        project_id: project_metadata.id,
                      )
                    }
                    _ -> NoAction(OptionMissing)
                  }
                }
              }
            }
            option.None -> {
              case
                resolution.find_field_and_option_ids(
                  status_fields,
                  config.status_field_name,
                  target_name,
                )
              {
                Ok(#(field_id, option_id, _opt_name)) -> {
                  MoveAction(
                    item_id: id,
                    field_id: field_id,
                    option_id: option_id,
                    option_name: target_name,
                    project_id: project_metadata.id,
                  )
                }
                _ -> NoAction(OptionMissing)
              }
            }
          }
        }
      }
    }
  }
}

/// Format the move plan as shell output messages
pub fn format_plan_result(
  plan: MovePlan,
  issue_number: Int,
  target_status_name: String,
  project_number: Int,
) -> String {
  case plan {
    NoAction(reason) -> {
      case reason {
        Disabled -> ""
        ItemMissing ->
          "⚠️ Issue #"
          <> int.to_string(issue_number)
          <> " is not linked to project #"
          <> int.to_string(project_number)
          <> ". Continuing without moving it to "
          <> target_status_name
          <> "."
        AlreadyInStatus(status) ->
          "📋 Issue #"
          <> int.to_string(issue_number)
          <> " is already in "
          <> status
          <> "."
        FieldMissing ->
          "❌ Unable to resolve the \""
          <> target_status_name
          <> "\" field for project #"
          <> int.to_string(project_number)
          <> "."
        OptionMissing ->
          "❌ Unable to resolve the \""
          <> target_status_name
          <> "\" option for project #"
          <> int.to_string(project_number)
          <> "."
      }
    }
    MoveAction(_, _, _, opt_name, _) -> {
      "✓ Planned move to " <> opt_name
    }
  }
}

/// Check if a plan represents a successful move
pub fn is_move_action(plan: MovePlan) -> Bool {
  case plan {
    MoveAction(_, _, _, _, _) -> True
    _ -> False
  }
}

/// Get the item ID from a move plan if available
pub fn get_item_id(plan: MovePlan) -> option.Option(String) {
  case plan {
    MoveAction(item_id, _, _, _, _) -> option.Some(item_id)
    _ -> option.None
  }
}

/// Get the field ID from a move plan if available
pub fn get_field_id(plan: MovePlan) -> option.Option(String) {
  case plan {
    MoveAction(_, field_id, _, _, _) -> option.Some(field_id)
    _ -> option.None
  }
}

/// Get the option ID from a move plan if available
pub fn get_option_id(plan: MovePlan) -> option.Option(String) {
  case plan {
    MoveAction(_, _, option_id, _, _) -> option.Some(option_id)
    _ -> option.None
  }
}

/// Get the project ID from a move plan if available
pub fn get_project_id(plan: MovePlan) -> option.Option(String) {
  case plan {
    MoveAction(_, _, _, _, project_id) -> option.Some(project_id)
    _ -> option.None
  }
}

/// Get the status name from a move plan if available
pub fn get_status_name(plan: MovePlan) -> option.Option(String) {
  case plan {
    MoveAction(_, _, _, status_name, _) -> option.Some(status_name)
    _ -> option.None
  }
}

/// Plan moving to Todo status
pub fn plan_move_to_todo(
  config: StatusConfig,
  project_metadata: ProjectMetadata,
  status_fields: List(StatusField),
  issue_json: String,
) -> MovePlan {
  plan_status_update(config, project_metadata, status_fields, issue_json, Todo)
}

/// Plan moving to In Progress status
pub fn plan_move_to_in_progress(
  config: StatusConfig,
  project_metadata: ProjectMetadata,
  status_fields: List(StatusField),
  issue_json: String,
) -> MovePlan {
  plan_status_update(
    config,
    project_metadata,
    status_fields,
    issue_json,
    InProgress,
  )
}

/// Plan moving to Done status
pub fn plan_move_to_done(
  config: StatusConfig,
  project_metadata: ProjectMetadata,
  status_fields: List(StatusField),
  issue_json: String,
) -> MovePlan {
  plan_status_update(config, project_metadata, status_fields, issue_json, Done)
}

/// Plan moving to Backlog status
pub fn plan_move_to_backlog(
  config: StatusConfig,
  project_metadata: ProjectMetadata,
  status_fields: List(StatusField),
  issue_json: String,
) -> MovePlan {
  plan_status_update(
    config,
    project_metadata,
    status_fields,
    issue_json,
    Backlog,
  )
}
