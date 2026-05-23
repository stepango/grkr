import gleeunit
import gleeunit/should

import grkr/github_picker/config
import grkr/github_picker/decoder
import grkr/github_picker/types.{
  ActiveJobsUnreadable, Config, Decode, InvalidPriorityMode,
  InvalidProjectNumber, IssueContent, MissingRequired, NoMatchingIssue, NoPriority,
  Number, NumberValue, ProjectItem, Query, Selection,
  SingleSelectValue,
}

pub fn main() {
  gleeunit.main()
}

pub fn job_key_for_issue_roundtrip_test() {
  types.job_key_for_issue(42)
  |> should.equal("issue:42:execution")

  types.job_key_for_issue(999)
  |> should.equal("issue:999:execution")
}

pub fn provider_error_to_string_test() {
  types.provider_error_to_string(Config(MissingRequired("REPO")))
  |> should.equal("Missing required config value: REPO")

  types.provider_error_to_string(Config(InvalidProjectNumber("abc")))
  |> should.equal("Invalid PROJECT_NUMBER: abc")

  types.provider_error_to_string(Config(InvalidPriorityMode("foo")))
  |> should.equal("Invalid PRIORITY_MODE: foo")

  types.provider_error_to_string(Config(ActiveJobsUnreadable("/bad/path")))
  |> should.equal("Could not read active jobs file: /bad/path")

  types.provider_error_to_string(Query("network fail"))
  |> should.equal("GitHub query failed: network fail")

  types.provider_error_to_string(Decode("bad json"))
  |> should.equal("GitHub decode failed: bad json")

  types.provider_error_to_string(Selection(NoMatchingIssue))
  |> should.equal("No matching Todo issue found in project")
}

pub fn selected_from_item_test() {
  let item =
    ProjectItem(
      project_item_id: "PVTI_xxx",
      content: IssueContent(
        number: 123,
        title: "Test issue",
        updated_at: "2026-05-01T10:00:00Z",
        state: "OPEN",
        repository: "stepango/grkr",
        assignee_logins: ["bot"],
      ),
      status_name: "Todo",
      priority: NumberValue(3),
    )

  let sel =
    types.selected_from_item(item, "", "3", "issue-123-test-issue")

  sel.issue_number |> should.equal(123)
  sel.job_key |> should.equal("issue:123:execution")
  sel.task_slug |> should.equal("issue-123-test-issue")
  sel.priority_number |> should.equal("3")
  sel.priority_name |> should.equal("")
}

pub fn make_test_config_roundtrip_test() {
  let cfg =
    config.make_test_config(
      "stepango/grkr",
      "stepango",
      5,
      "Todo",
      Number,
      ["P0", "P1"],
      "bot",
    )

  cfg.repo |> should.equal("stepango/grkr")
  cfg.project_number |> should.equal(5)
  cfg.priority_mode |> should.equal(Number)
  cfg.active_jobs |> should.equal([])
  cfg.todo_value |> should.equal("Todo")
}

pub fn priority_value_construction_test() {
  let n = NumberValue(10)
  let s = SingleSelectValue("P0")
  let none = NoPriority

  // different variants are not equal
  n |> should.not_equal(s)
  none |> should.not_equal(n)
}

pub fn decode_project_items_json_roundtrip_test() {
  // JSON decoding test using minimal valid shape (items array for decoder)
  let cfg =
    config.make_test_config(
      "stepango/grkr",
      "stepango",
      1,
      "Todo",
      Number,
      [],
      "bot",
    )

  // empty items
  decoder.decode_project_items("{\"items\": []}", cfg)
  |> should.equal(Ok([]))

  // bad json -> error (covers decode path)
  decoder.decode_project_items("{not valid json", cfg)
  |> should.be_error()
}
