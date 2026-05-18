import gleeunit
import gleeunit/should

import grkr/github_picker/config
import grkr/github_picker/types.{Number, SingleSelect}

pub fn main() {
  gleeunit.main()
}

pub fn priority_mode_from_string_test() {
  types.priority_mode_from_string("number")
  |> should.equal(Number)

  types.priority_mode_from_string("NUMBER")
  |> should.equal(Number)

  types.priority_mode_from_string("single_select")
  |> should.equal(SingleSelect)

  types.priority_mode_from_string("select")
  |> should.equal(SingleSelect)

  types.priority_mode_from_string("")
  |> should.equal(SingleSelect)

  types.priority_mode_from_string("foo")
  |> should.equal(SingleSelect)
}

pub fn normalize_priority_mode_test() {
  types.normalize_priority_mode("number")
  |> should.equal("number")

  types.normalize_priority_mode("single_select")
  |> should.equal("single_select")

  types.normalize_priority_mode("Number")
  |> should.equal("number")

  types.normalize_priority_mode("foo")
  |> should.equal("")
}

pub fn job_key_for_issue_test() {
  types.job_key_for_issue(123)
  |> should.equal("issue:123:execution")
}

pub fn make_test_config_test() {
  let cfg =
    config.make_test_config(
      "stepango/grkr",
      "stepango",
      1,
      "Todo",
      Number,
      ["P0", "P1"],
      "robot",
    )

    cfg.repo |> should.equal("stepango/grkr")
  cfg.project_owner |> should.equal("stepango")
  cfg.project_number |> should.equal(1)
  cfg.todo_value |> should.equal("Todo")
  cfg.priority_mode |> should.equal(Number)
  cfg.priority_order |> should.equal(["P0", "P1"])
  cfg.active_jobs |> should.equal([])
  cfg.grkr_root |> should.equal(".grkr")
  cfg.status_field_name |> should.equal("Status")
  cfg.priority_field_name |> should.equal("Priority")
}

pub fn load_returns_error_without_env_test() {
  // load requires REPO etc in env; in test env without them it should error
  // this is non-deterministic on env but documents the behavior
  case config.load() {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}
