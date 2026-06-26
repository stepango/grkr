import gleam/int
import gleam/option.{type Option, None, Some}

import grkr/progress/checkpoint_id
import grkr/progress/checkpoint_stage
import grkr/refusal/ffi
import grkr/refusal/types.{
  type RefusalClass,
  MissingDependency, NeedsDesignDecision, Other, RepoNotReady,
  TooLarge, Underspecified, UnsafeAutonomousChange,
  to_string,
}

/// Pure markdown helpers for refusal assessment output (port of bash refusal_*_markdown fns).
/// Used by format_full and later by flow/checkpoint render.

pub fn missing_requirements_markdown(class: RefusalClass) -> String {
  case class {
    Underspecified ->
      "- Explicit acceptance criteria or expected behavior examples\n- Clear success conditions for the implementation and test stages"
    TooLarge ->
      "- A smaller, explicitly scoped first slice of work\n- A concrete split between independent follow-up issues"
    MissingDependency ->
      "- The missing upstream dependency, API, or prerequisite issue\n- Confirmation that the dependency is available in the target branch"
    NeedsDesignDecision ->
      "- A concrete design or product decision for the ambiguous behavior\n- Confirmation of the preferred implementation direction"
    UnsafeAutonomousChange ->
      "- Human review for the risky change path\n- A safer bounded approach or rollback strategy"
    RepoNotReady ->
      "- Repository health restored enough for issue-local changes to be validated\n- Confirmation that unrelated build or test failures are resolved"
    Other(_) ->
      "- The missing prerequisite identified in the refusal reasoning above\n- A narrower, directly testable issue scope"
  }
}

pub fn next_steps_markdown(class: RefusalClass) -> String {
  case class {
    TooLarge ->
      "- Split the issue into smaller independently testable tasks\n- Re-run the workflow against the first bounded slice"
    _ ->
      "- Update the issue with the missing detail identified above\n- Re-run the workflow after the issue is clarified and bounded"
  }
}

pub fn split_recommendation(class: RefusalClass) -> String {
  case class {
    TooLarge | UnsafeAutonomousChange ->
      "Yes. The current issue is too broad for one safe autonomous change."
    _ ->
      "No immediate split is required if the missing prerequisite can be resolved directly in this issue."
  }
}

pub fn follow_up_recommendation(class: RefusalClass) -> String {
  case class {
    TooLarge | MissingDependency | NeedsDesignDecision ->
      "Yes. Follow-up issues are recommended to separate prerequisite or decision work."
    _ ->
      "Not necessarily. The current issue may proceed once the missing information is added."
  }
}

/// Build the full refusal.md / comment body matching bash + spec example.
/// Includes checkpoint marker, structured sections, per-class recommendations.
/// GitHub-only v2.
pub fn format_full_refusal_md(
  task_slug: String,
  issue_number: Option(Int),
  title: String,
  class: RefusalClass,
  reasoning: String,
) -> String {
  let marker =
    checkpoint_id.marker(checkpoint_stage.Refusal, task_slug)
    |> checkpoint_id.to_html_comment()

  let issue_line = case issue_number {
    Some(n) -> "Issue #" <> int.to_string(n) <> ": " <> title
    None -> title
  }

  let class_s = to_string(class)
  let needed = missing_requirements_markdown(class)
  let nexts = next_steps_markdown(class)
  let split = split_recommendation(class)
  let followup = follow_up_recommendation(class)
  let summary_line = refusal_summary_line()

  marker
  <> "\n\n## Implementation refused\n\n"
  <> issue_line
  <> "\n\n"
  <> "### Refusal summary\n\n"
  <> summary_line
  <> "\n\n"
  <> "### Reason class\n\n"
  <> class_s
  <> "\n\n"
  <> "### Detailed reasoning\n\n"
  <> reasoning
  <> "\n\n"
  <> "### What is needed before implementation\n\n"
  <> needed
  <> "\n\n"
  <> "### Suggested next actions\n\n"
  <> nexts
  <> "\n\n"
  <> "### Should the issue be split?\n\n"
  <> split
  <> "\n\n"
  <> "### Are follow-up issues recommended?\n\n"
  <> followup
  <> "\n"
}

fn refusal_summary_line() -> String {
  case ffi.get_env_with_default("GRKR_REFUSAL_SUMMARY", "") {
    "implementation_after_proceed" ->
      "The issue was not implemented because implementation discovered a blocker after the decision gate returned `proceed`."
    _ ->
      "The issue was not implemented because the decision gate returned `refuse`."
  }
}
