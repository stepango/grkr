import gleam/list
import gleam/option.{type Option, None, Some}

/// GitHub Project status update configuration
pub type StatusConfig {
  StatusConfig(
    updates_enabled: Bool,
    project_owner: String,
    project_number: Int,
    status_field_name: String,
    todo_value: String,
    in_progress_value: String,
    done_value: String,
    backlog_value: String,
  )
}

/// A single status option within a status field
pub type StatusOption {
  StatusOption(id: String, name: String)
}

/// A status field with its options
pub type StatusField {
  StatusField(id: String, name: String, options: List(StatusOption))
}

/// Project metadata from gh project view
pub type ProjectMetadata {
  ProjectMetadata(id: String, number: Int, owner: String)
}

/// A project item (issue) with its status
pub type ProjectItem {
  ProjectItem(
    id: String,
    content_number: Int,
    status_name: Option(String),
    project_number: Option(Int),
  )
}

/// Result type for project status operations
pub type StatusError {
  UpdatesDisabled
  ItemNotFound
  FieldNotFound(field_name: String)
  OptionNotFound(option_name: String)
  ProjectNotFound
  InvalidJson(reason: String)
  AlreadyInTargetStatus(current: String, target: String)
}

/// Planned status update with all required information
pub type MovePlan {
  NoAction(reason: NoActionReason)
  MoveAction(
    item_id: String,
    field_id: String,
    option_id: String,
    option_name: String,
    project_id: String,
  )
}

/// Reasons for not performing a move
pub type NoActionReason {
  Disabled
  ItemMissing
  AlreadyInStatus(status: String)
  FieldMissing
  OptionMissing
}

/// Target status type
pub type TargetStatus {
  Todo
  InProgress
  Done
  Backlog
  Custom(String)
}

/// Parsed gh project field-list output
pub type ProjectFields {
  ProjectFields(fields: List(StatusField))
}

/// Extract a status option by normalized name
pub fn find_option_by_name(
  field: StatusField,
  target_name: String,
  normalize: fn(String) -> String,
) -> Option(StatusOption) {
  let normalized_target = normalize(target_name)

  let found =
    field.options
    |> list.find(fn(opt) {
      let normalized_opt = normalize(opt.name)
      normalized_opt == normalized_target
    })
  case found {
    Ok(option) -> Some(option)
    Error(_) -> None
  }
}

/// Check if updates are enabled
pub fn is_updates_enabled(config: StatusConfig) -> Bool {
  config.updates_enabled
}
