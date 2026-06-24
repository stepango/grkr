import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import grkr/github_picker/types as github_types
import grkr/issue_provider/types as linear_types
import grkr/supervisor/pick

@external(javascript, "./test_helper.mjs", "set_env")
fn set_env(name: String, value: String) -> Nil

pub fn main() {
  gleeunit.main()
}

pub fn from_github_maps_selected_work_test() {
  let sel =
    github_types.SelectedGitHubIssue(
      project_item_id: "PVTI_pick1",
      issue_number: 42,
      issue_title: "Fixture pick issue",
      issue_updated_at: "2026-03-10T10:00:00Z",
      priority_name: "P0",
      priority_number: "",
      job_key: "issue:42:execution",
      task_slug: "issue-42-fixture-pick-issue",
    )

  let work = pick.from_github(sel)
  work.provider |> should.equal("github")
  work.issue_number |> should.equal(Some(42))
  work.identifier |> should.equal(None)
  work.job_key |> should.equal("issue:42:execution")
  work.project_item_id |> should.equal(Some("PVTI_pick1"))
}

pub fn from_linear_maps_selected_work_test() {
  let sel =
    linear_types.SelectedIssue(
      identifier: "ENG-123",
      title: "Linear task",
      url: "https://linear.app/issue/ENG-123",
      state_name: "Todo",
      priority: linear_types.High,
      updated_at: "2026-04-28T12:00:00Z",
    )

  let work = pick.from_linear(sel)
  work.provider |> should.equal("linear")
  work.issue_number |> should.equal(None)
  work.identifier |> should.equal(Some("ENG-123"))
  work.job_key |> should.equal("linear:ENG-123:execution")
  work.task_slug |> should.equal("eng-123")
}

pub fn issue_provider_name_defaults_github_test() {
  set_env("GRKR_ISSUE_PROVIDER", "")
  pick.issue_provider_name() |> should.equal("github")
}

pub fn pick_next_github_fixture_test() {
  let root = fixture_root()
  set_env("GRKR_ISSUE_PROVIDER", "github")
  set_env("REPO", "stepango/grkr")
  set_env("PROJECT_OWNER", "stepango")
  set_env("PROJECT_NUMBER", "1")
  set_env("BOT_LOGIN", "robot")
  set_env("GITHUB_FIXTURE_PATH", root <> "/test/fixtures/github-project-items.json")
  set_env("GRKR_ACTIVE_JOBS_PATH", root <> "/test/fixtures/empty-active-jobs.json")

  case pick.pick_next() {
    Ok(work) -> {
      work.provider |> should.equal("github")
      work.issue_number |> should.equal(Some(42))
      work.job_key |> should.equal("issue:42:execution")
    }
    Error(_) -> should.fail()
  }
}

pub fn pick_next_linear_fixture_test() {
  let root = fixture_root()
  set_env("GRKR_ISSUE_PROVIDER", "linear")
  set_env("LINEAR_ASSIGNEE_ID", "u1")
  set_env("LINEAR_FIXTURE_PATH", root <> "/test/fixtures/linear-assigned-issues.json")

  case pick.pick_next() {
    Ok(work) -> {
      work.provider |> should.equal("linear")
      work.identifier |> should.equal(Some("ENG-123"))
      work.job_key |> should.equal("linear:ENG-123:execution")
      work.task_slug |> should.equal("eng-123")
    }
    Error(_) -> should.fail()
  }
}

pub fn schedule_success_log_fields_github_test() {
  let work =
    pick.SelectedWork(
      issue_number: Some(42),
      identifier: None,
      issue_title: "t",
      job_key: "issue:42:execution",
      task_slug: "issue-42-fixture-pick-issue",
      project_item_id: Some("PVTI_pick1"),
      provider: "github",
    )
  let msg = pick.schedule_success_log_fields(work)
  string.contains(msg, "selected_issue=42") |> should.be_true()
  string.contains(msg, "task_slug=issue-42-fixture-pick-issue") |> should.be_true()
}

pub fn schedule_pending_log_fields_linear_test() {
  let work =
    pick.SelectedWork(
      issue_number: None,
      identifier: Some("ENG-123"),
      issue_title: "t",
      job_key: "linear:ENG-123:execution",
      task_slug: "eng-123",
      project_item_id: None,
      provider: "linear",
    )
  let msg = pick.schedule_pending_log_fields(work)
  string.contains(msg, "selected_issue_missing_number=true") |> should.be_true()
  string.contains(msg, "identifier=ENG-123") |> should.be_true()
}

fn fixture_root() -> String {
  // Repo root when tests run via `gleam test` from project directory.
  case std_getcwd() {
    Ok(path) -> path
    Error(_) -> "."
  }
}

@external(javascript, "./fixture_root.mjs", "getcwd")
fn std_getcwd() -> Result(String, Nil)