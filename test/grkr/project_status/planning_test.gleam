import gleam/string
import gleeunit
import gleeunit/should
import grkr/project_status/planning
import grkr/project_status/types.{
  type ProjectMetadata, type StatusConfig, type StatusField, AlreadyInStatus,
  Disabled, InProgress, ItemMissing, MoveAction, NoAction, ProjectMetadata,
  StatusConfig, StatusField, StatusOption, Todo,
}

pub fn main() {
  gleeunit.main()
}

fn test_config() -> StatusConfig {
  StatusConfig(
    updates_enabled: True,
    project_owner: "stepango",
    project_number: 1,
    status_field_name: "Status",
    todo_value: "Todo",
    in_progress_value: "In Progress",
    done_value: "Done",
    backlog_value: "Backlog",
  )
}

fn test_project_metadata() -> ProjectMetadata {
  ProjectMetadata(id: "PROJ_1", number: 1, owner: "stepango")
}

fn test_status_fields() -> List(StatusField) {
  [
    StatusField(id: "F_1", name: "Status", options: [
      StatusOption(id: "O_1", name: "Todo"),
      StatusOption(id: "O_2", name: "In Progress"),
      StatusOption(id: "O_3", name: "Done"),
      StatusOption(id: "O_4", name: "Backlog"),
    ]),
  ]
}

pub fn plan_status_update_disabled_test() {
  let config =
    StatusConfig(
      updates_enabled: False,
      project_owner: "stepango",
      project_number: 1,
      status_field_name: "Status",
      todo_value: "Todo",
      in_progress_value: "In Progress",
      done_value: "Done",
      backlog_value: "Backlog",
    )

  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":1},\"status\":{\"name\":\"Todo\"}}]}"

  let plan =
    planning.plan_status_update(
      config,
      test_project_metadata(),
      test_status_fields(),
      issue_json,
      Todo,
    )

  plan
  |> should.equal(NoAction(Disabled))
}

pub fn plan_status_update_item_missing_test() {
  let issue_json = "{\"projectItems\":[]}"

  let plan =
    planning.plan_status_update(
      test_config(),
      test_project_metadata(),
      test_status_fields(),
      issue_json,
      Todo,
    )

  plan
  |> should.equal(NoAction(ItemMissing))
}

pub fn plan_status_update_already_in_status_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":1},\"status\":{\"name\":\"Todo\"}}]}"

  let plan =
    planning.plan_status_update(
      test_config(),
      test_project_metadata(),
      test_status_fields(),
      issue_json,
      Todo,
    )

  case plan {
    NoAction(AlreadyInStatus(status)) -> {
      status
      |> should.equal("Todo")
    }
    _ -> {
      should.fail()
    }
  }
}

pub fn plan_status_update_valid_move_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":1},\"status\":{\"name\":\"Todo\"}}]}"

  let plan =
    planning.plan_status_update(
      test_config(),
      test_project_metadata(),
      test_status_fields(),
      issue_json,
      InProgress,
    )

  case plan {
    MoveAction(item_id, field_id, option_id, opt_name, project_id) -> {
      item_id
      |> should.equal("PVTI_123")

      field_id
      |> should.equal("F_1")

      option_id
      |> should.equal("O_2")

      opt_name
      |> should.equal("In Progress")

      project_id
      |> should.equal("PROJ_1")
    }
    _ -> {
      should.fail()
    }
  }
}

pub fn plan_move_to_backlog_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":1},\"status\":{\"name\":\"Todo\"}}]}"

  let plan =
    planning.plan_move_to_backlog(
      test_config(),
      test_project_metadata(),
      test_status_fields(),
      issue_json,
    )

  case plan {
    MoveAction(_, _, _, opt_name, _) -> {
      opt_name
      |> should.equal("Backlog")
    }
    _ -> {
      should.fail()
    }
  }
}

pub fn plan_move_to_done_test() {
  let issue_json =
    "{\"projectItems\":[{\"id\":\"PVTI_123\",\"project\":{\"number\":1},\"status\":{\"name\":\"In Progress\"}}]}"

  let plan =
    planning.plan_move_to_done(
      test_config(),
      test_project_metadata(),
      test_status_fields(),
      issue_json,
    )

  case plan {
    MoveAction(_, _, _, opt_name, _) -> {
      opt_name
      |> should.equal("Done")
    }
    _ -> {
      should.fail()
    }
  }
}

pub fn is_move_action_test() {
  planning.is_move_action(MoveAction("id", "fid", "oid", "name", "pid"))
  |> should.be_true()

  planning.is_move_action(NoAction(Disabled))
  |> should.be_false()
}

pub fn format_plan_result_item_missing_test() {
  let plan = NoAction(ItemMissing)

  let result = planning.format_plan_result(plan, 42, "In Progress", 1)

  string.contains(result, "is not linked to project")
  |> should.be_true()
}

pub fn format_plan_result_already_in_status_test() {
  let plan = NoAction(AlreadyInStatus("Todo"))

  let result = planning.format_plan_result(plan, 42, "Todo", 1)

  string.contains(result, "is already in")
  |> should.be_true()
}
