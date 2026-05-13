import gleeunit
import gleeunit/should
import grkr/project_status/types

pub fn main() {
  gleeunit.main()
}

pub fn is_updates_enabled_test() {
  let config =
    types.StatusConfig(
      updates_enabled: True,
      project_owner: "stepango",
      project_number: 1,
      status_field_name: "Status",
      todo_value: "Todo",
      in_progress_value: "In Progress",
      done_value: "Done",
      backlog_value: "Backlog",
    )

  types.is_updates_enabled(config)
  |> should.equal(True)

  let config_disabled =
    types.StatusConfig(
      updates_enabled: False,
      project_owner: "stepango",
      project_number: 1,
      status_field_name: "Status",
      todo_value: "Todo",
      in_progress_value: "In Progress",
      done_value: "Done",
      backlog_value: "Backlog",
    )

  types.is_updates_enabled(config_disabled)
  |> should.equal(False)
}
