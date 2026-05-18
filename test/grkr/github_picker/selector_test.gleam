import gleam/int
import gleam/list

import gleeunit
import gleeunit/should

import grkr/github_picker/config
import grkr/github_picker/selector
import grkr/github_picker/types.{
  type Candidate,
  type GitHubPickerConfig,
  type IssueContent,
  type PriorityMode,
  type PriorityValue,
  type ProjectItem,
  NoPriority,
  Number,
  NumberValue,
  SingleSelect,
  SingleSelectValue,
}

pub fn main() {
  gleeunit.main()
}

fn make_item(
  number: Int,
  status: String,
  state: String,
  repo: String,
  priority: types.PriorityValue,
  updated_at: String,
) -> ProjectItem {
  ProjectItem(
    project_item_id: "item_" <> int.to_string(number),
    content: IssueContent(
      number: number,
      title: "Test issue " <> int.to_string(number),
      updated_at: updated_at,
      state: state,
      repository: repo,
      assignee_logins: ["bot"],
    ),
    status_name: status,
    priority: priority,
  )
}

fn base_cfg(mode: types.PriorityMode, order: List(String)) -> GitHubPickerConfig {
  config.make_test_config(
    "stepango/grkr",
    "stepango",
    1,
    "Todo",
    mode,
    order,
    "bot",
  )
}

fn cfg_with_active(
  mode: types.PriorityMode,
  order: List(String),
  active: List(String),
) -> GitHubPickerConfig {
  let base = base_cfg(mode, order)
  GitHubPickerConfig(
    repo: base.repo,
    project_owner: base.project_owner,
    project_number: base.project_number,
    status_field_name: base.status_field_name,
    todo_value: base.todo_value,
    priority_field_name: base.priority_field_name,
    priority_mode: base.priority_mode,
    priority_order: base.priority_order,
    active_jobs: active,
    grkr_root: base.grkr_root,
    bot_login: base.bot_login,
  )
}

pub fn compute_priority_sort_number_test() {
  let cfg = base_cfg(Number, [])
  selector.compute_priority_sort(NumberValue(5), Number, cfg.priority_order)
  |> should.equal(-5)

  selector.compute_priority_sort(NoPriority, Number, cfg.priority_order)
  |> should.equal(0)
}

pub fn compute_priority_sort_single_select_test() {
  let order = ["P0", "P1", "P2"]
  let cfg = base_cfg(SingleSelect, order)

  selector.compute_priority_sort(SingleSelectValue("P1"), SingleSelect, order)
  |> should.equal(1)

  selector.compute_priority_sort(SingleSelectValue("P0"), SingleSelect, order)
  |> should.equal(0)

  selector.compute_priority_sort(NoPriority, SingleSelect, order)
  |> should.equal(4)

  selector.compute_priority_sort(SingleSelectValue("unknown"), SingleSelect, order)
  |> should.equal(4)
}

pub fn is_candidate_basic_test() {
  let cfg = base_cfg(Number, [])
  let item =
    make_item(42, "Todo", "OPEN", "stepango/grkr", NumberValue(1), "2026-01-01T00:00:00Z")

  selector.is_candidate(item, cfg) |> should.be_true()
}

pub fn is_candidate_filters_test() {
  let cfg = base_cfg(Number, [])
  let todo_closed =
    make_item(1, "Todo", "CLOSED", "stepango/grkr", NoPriority, "2026-01-01")
  let wrong_status =
    make_item(2, "In Progress", "OPEN", "stepango/grkr", NoPriority, "2026-01-01")
  let wrong_repo =
    make_item(3, "Todo", "OPEN", "other/repo", NoPriority, "2026-01-01")

  selector.is_candidate(todo_closed, cfg) |> should.be_false()
  selector.is_candidate(wrong_status, cfg) |> should.be_false()
  selector.is_candidate(wrong_repo, cfg) |> should.be_false()
}

pub fn is_candidate_active_jobs_filter_test() {
  let cfg = cfg_with_active(Number, [], ["issue:42:execution"])
  let active_item =
    make_item(42, "Todo", "OPEN", "stepango/grkr", NumberValue(0), "2026-01-01")
  let normal_item =
    make_item(43, "Todo", "OPEN", "stepango/grkr", NumberValue(1), "2026-01-01")

  selector.is_candidate(active_item, cfg) |> should.be_false()
  selector.is_candidate(normal_item, cfg) |> should.be_true()
}

pub fn to_candidates_test() {
  let order = ["P0", "P1"]
  let cfg = base_cfg(SingleSelect, order)
  let items = [
    make_item(10, "Todo", "OPEN", "stepango/grkr", SingleSelectValue("P1"), "2026-01-01"),
    make_item(11, "Todo", "OPEN", "stepango/grkr", SingleSelectValue("P0"), "2026-01-02"),
  ]

  let cands = selector.to_candidates(items, cfg)
  list.length(cands) |> should.equal(2)
  // P0 should have lower sort (0) than P1 (1)
  case cands {
    [c0, c1] -> {
      c0.item.content.number |> should.equal(11)
      c1.item.content.number |> should.equal(10)
    }
    _ -> should.fail()
  }
}

pub fn select_best_priority_test() {
  let cfg = base_cfg(Number, [])
  let items = [
    make_item(100, "Todo", "OPEN", "stepango/grkr", NumberValue(5), "2026-01-01"),
    make_item(101, "Todo", "OPEN", "stepango/grkr", NumberValue(1), "2026-01-01"),
  ]
  let cands = selector.to_candidates(items, cfg)
  case selector.select_best(cands) {
    Ok(best) -> best.content.number |> should.equal(101)
    Error(_) -> should.fail()
  }
}

pub fn select_best_updated_at_tiebreaker_test() {
  let cfg = base_cfg(Number, [])
  let items = [
    // same priority, newer first in list, should pick older (smaller updated string)
    make_item(200, "Todo", "OPEN", "stepango/grkr", NoPriority, "2026-01-02T00:00:00Z"),
    make_item(201, "Todo", "OPEN", "stepango/grkr", NoPriority, "2026-01-01T00:00:00Z"),
  ]
  let cands = selector.to_candidates(items, cfg)
  case selector.select_best(cands) {
    Ok(best) -> best.content.number |> should.equal(201)
    Error(_) -> should.fail()
  }
}

pub fn select_best_number_tiebreaker_test() {
  let cfg = base_cfg(Number, [])
  let items = [
    make_item(300, "Todo", "OPEN", "stepango/grkr", NoPriority, "2026-01-01"),
    make_item(299, "Todo", "OPEN", "stepango/grkr", NoPriority, "2026-01-01"),
  ]
  let cands = selector.to_candidates(items, cfg)
  case selector.select_best(cands) {
    Ok(best) -> best.content.number |> should.equal(299)
    Error(_) -> should.fail()
  }
}

pub fn pick_success_test() {
  let order = ["P0", "P1"]
  let cfg = base_cfg(SingleSelect, order)
  let items = [
    make_item(55, "Todo", "OPEN", "stepango/grkr", SingleSelectValue("P0"), "2026-05-01"),
  ]
  case selector.pick(items, cfg) {
    Ok(sel) -> {
      sel.issue_number |> should.equal(55)
      sel.priority_name |> should.equal("P0")
      sel.job_key |> should.equal("issue:55:execution")
    }
    Error(_) -> should.fail()
  }
}

pub fn pick_no_match_test() {
  let cfg = base_cfg(Number, [])
  let items = [
    make_item(99, "Done", "OPEN", "stepango/grkr", NoPriority, "2026-01-01"),
  ]
  selector.pick(items, cfg) |> should.be_error()
}
