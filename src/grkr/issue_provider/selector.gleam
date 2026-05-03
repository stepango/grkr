import gleam/list
import gleam/order
import gleam/string
import grkr/issue_provider/types

/// Compare two issues by priority, then updated_at, then identifier
fn compare_issues(
  priority_order: types.PriorityOrder,
  a: types.LinearIssue,
  b: types.LinearIssue,
) -> order.Order {
  let a_weight = types.priority_weight(priority_order, a.priority)
  let b_weight = types.priority_weight(priority_order, b.priority)

  case a_weight, b_weight {
    w_a, w_b if w_a < w_b -> order.Lt
    w_a, w_b if w_a > w_b -> order.Gt
    _, _ -> {
      case string.compare(a.updated_at, b.updated_at) {
        order.Lt -> order.Lt
        order.Gt -> order.Gt
        order.Eq -> string.compare(a.identifier, b.identifier)
      }
    }
  }
}

/// Check if an issue matches the filter criteria
fn matches_filter(issue: types.LinearIssue, filter: types.IssueFilter) -> Bool {
  let state_match = issue.state.name == filter.state_name

  let assignee_match = case issue.assignee {
    Ok(assignee) -> assignee.id == filter.assignee_id
    Error(Nil) -> False
  }

  let project_match = case filter.project_id {
    Ok(project_id) -> {
      case issue.project {
        Ok(project) -> project.id == project_id
        Error(Nil) -> False
      }
    }
    Error(Nil) -> True
  }

  let team_match = case filter.team_id {
    Ok(team_id) -> {
      case issue.team {
        Ok(team) -> team.id == team_id
        Error(Nil) -> False
      }
    }
    Error(Nil) -> True
  }

  state_match && assignee_match && project_match && team_match
}

/// Filter issues by the given criteria
pub fn filter_issues(
  issues: List(types.LinearIssue),
  filter: types.IssueFilter,
) -> List(types.LinearIssue) {
  list.filter(issues, fn(issue) { matches_filter(issue, filter) })
}

/// Select the highest priority issue from the list
pub fn select_highest_priority(
  issues: List(types.LinearIssue),
  priority_order: types.PriorityOrder,
) -> Result(types.LinearIssue, Nil) {
  case issues {
    [] -> Error(Nil)
    _ -> {
      let sorted =
        list.sort(issues, fn(a, b) { compare_issues(priority_order, a, b) })

      case list.first(sorted) {
        Ok(issue) -> Ok(issue)
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

/// Select the best matching issue from a list using the filter
pub fn select_issue(
  issues: List(types.LinearIssue),
  filter: types.IssueFilter,
  priority_order: types.PriorityOrder,
) -> types.SelectionResult {
  let filtered = filter_issues(issues, filter)
  let count = list.length(filtered)

  case select_highest_priority(filtered, priority_order) {
    Ok(issue) ->
      types.SelectionSuccess(
        selected: types.issue_to_selected(issue),
        total_candidates: count,
      )
    Error(Nil) -> types.NoMatchingIssues
  }
}

/// Create a default filter from state name and assignee ID
pub fn default_filter(
  state_name: String,
  assignee_id: String,
) -> types.IssueFilter {
  types.make_filter(state_name, assignee_id, Error(Nil), Error(Nil))
}

/// Create a project-scoped filter
pub fn project_filter(
  state_name: String,
  assignee_id: String,
  project_id: String,
) -> types.IssueFilter {
  types.make_filter(state_name, assignee_id, Ok(project_id), Error(Nil))
}

/// Create a team-scoped filter
pub fn team_filter(
  state_name: String,
  assignee_id: String,
  team_id: String,
) -> types.IssueFilter {
  types.make_filter(state_name, assignee_id, Error(Nil), Ok(team_id))
}

/// Normalize state name for comparison (case-insensitive, trimmed)
pub fn normalize_state_name(state: String) -> String {
  state
  |> string.trim
  |> string.lowercase
}

/// Check if two state names match after normalization
pub fn state_names_match(a: String, b: String) -> Bool {
  normalize_state_name(a) == normalize_state_name(b)
}

/// Validate that an issue's state matches the expected state
pub fn validate_issue_state(
  issue: types.LinearIssue,
  expected_state: String,
) -> Bool {
  state_names_match(issue.state.name, expected_state)
}
