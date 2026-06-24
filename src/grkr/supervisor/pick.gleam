//// supervisor/pick.gleam
//// Unified issue pick for the supervisor pick_and_schedule phase.
//// Dispatches on GRKR_ISSUE_PROVIDER (default github) to github_picker or issue_provider.

import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string

import grkr/github_picker/main as github_picker
import grkr/github_picker/types as github_types
import grkr/issue_provider/main as linear_picker
import grkr/issue_provider/types as linear_types
import grkr/supervisor/ffi
import grkr/supervisor/scheduler
import grkr/supervisor/types as t

/// Provider-agnostic pick result for scheduling and logging.
pub type SelectedWork {
  SelectedWork(
    issue_number: Option(Int),
    identifier: Option(String),
    issue_title: String,
    job_key: String,
    task_slug: String,
    project_item_id: Option(String),
    provider: String,
  )
}

pub type PickError {
  NoMatchingIssue
  Failed(reason: String)
}

pub fn pick_error_to_string(e: PickError) -> String {
  case e {
    NoMatchingIssue -> "no_matching_issue"
    Failed(r) -> r
  }
}

/// Read GRKR_ISSUE_PROVIDER; default github when unset or empty.
pub fn issue_provider_name() -> String {
  let raw = string.lowercase(string.trim(ffi.get_env("GRKR_ISSUE_PROVIDER")))
  case raw {
    "" -> "github"
    "linear" -> "linear"
    other -> other
  }
}

/// Pick the next issue from the configured provider (fixture-aware via env).
pub fn pick_next() -> Result(SelectedWork, PickError) {
  case issue_provider_name() {
    "linear" -> pick_linear()
    _ -> pick_github()
  }
}

pub fn from_github(sel: github_types.SelectedGitHubIssue) -> SelectedWork {
  let proj = case sel.project_item_id {
    "" -> None
    id -> Some(id)
  }
  SelectedWork(
    issue_number: Some(sel.issue_number),
    identifier: None,
    issue_title: sel.issue_title,
    job_key: sel.job_key,
    task_slug: sel.task_slug,
    project_item_id: proj,
    provider: "github",
  )
}

pub fn from_linear(sel: linear_types.SelectedIssue) -> SelectedWork {
  SelectedWork(
    issue_number: None,
    identifier: Some(sel.identifier),
    issue_title: sel.title,
    job_key: linear_types.job_key_for_identifier(sel.identifier),
    task_slug: linear_types.task_slug_for_identifier(sel.identifier),
    project_item_id: None,
    provider: "linear",
  )
}

/// Schedule execution for a picked issue. GitHub uses spawn_issue_execution;
/// Linear scheduling is added in a follow-up card (logs pending when identifier-only).
pub fn schedule_selected(
  config: t.SupervisorConfig,
  work: SelectedWork,
) -> Result(Bool, t.SupervisorError) {
  case work.issue_number {
    Some(n) -> {
      case scheduler.spawn_issue_execution(config, n, work.task_slug, work.project_item_id) {
        Ok(_) -> Ok(True)
        Error(e) -> Error(e)
      }
    }
    None -> Ok(False)
  }
}

fn pick_github() -> Result(SelectedWork, PickError) {
  case github_picker.pick_next() {
    Ok(sel) -> Ok(from_github(sel))
    Error(e) -> Error(map_github_error(e))
  }
}

fn pick_linear() -> Result(SelectedWork, PickError) {
  case linear_picker.run() {
    Ok(sel) -> Ok(from_linear(sel))
    Error(e) -> Error(map_linear_error(e))
  }
}

fn map_github_error(e: github_types.ProviderError) -> PickError {
  case e {
    github_types.Selection(github_types.NoMatchingIssue) -> NoMatchingIssue
    _ -> Failed(github_types.provider_error_to_string(e))
  }
}

fn map_linear_error(e: linear_types.ProviderError) -> PickError {
  case e {
    linear_types.NoMatchingIssue -> NoMatchingIssue
    _ -> Failed(linear_types.provider_error_to_string(e))
  }
}

/// Log fields for the pick phase (provider + ids).
pub fn selected_log_fields(work: SelectedWork) -> String {
  let inum = case work.issue_number {
    Some(n) -> int.to_string(n)
    None -> "-"
  }
  let ident = case work.identifier {
    Some(i) -> i
    None -> "-"
  }
  "provider="
    <> work.provider
    <> " issue_number="
    <> inum
    <> " identifier="
    <> ident
    <> " job_key="
    <> work.job_key
    <> " task_slug="
    <> work.task_slug
}

/// Shell-parity fields for pick_and_schedule success logs (robot-main-schedules-issue.sh).
pub fn schedule_success_log_fields(work: SelectedWork) -> String {
  let base = selected_log_fields(work)
  case work.issue_number {
    Some(n) ->
      base <> " selected_issue=" <> int.to_string(n)
    None -> base
  }
}

/// Shell-parity fields when pick succeeded but execution spawn is deferred (Linear).
pub fn schedule_pending_log_fields(work: SelectedWork) -> String {
  "selected_issue_missing_number=true "
    <> selected_log_fields(work)
}