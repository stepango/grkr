import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

import grkr/github_picker/types
import grkr/task_slug

/// Sentinel for no-priority (lowest) in sort key. Safe for JS number ( < 2^53 )
/// Compute numeric sort key for priority (lower number = higher urgency, comes first in sort)
pub fn compute_priority_sort(
  prio: types.PriorityValue,
  mode: types.PriorityMode,
  order: List(String),
) -> Int {
  case mode {
    types.Number ->
      case prio {
        types.NumberValue(n) -> 0 - n
        _ -> 0
      }
    types.SingleSelect ->
      case prio {
        types.SingleSelectValue(name) -> index_of(order, name)
        _ -> list.length(order) + 1
      }
  }
}

fn index_of(list: List(String), item: String) -> Int {
  list
  |> list.index_map(fn(x, i) { #(x, i) })
  |> list.find(fn(p) { p.0 == item })
  |> result.map(fn(p) { p.1 })
  |> result.unwrap(list.length(list) + 1)
}

/// Check if item is a valid candidate for picking:
/// - Status matches todo_value
/// - State is OPEN (case insensitive)
/// - Repository matches (normalized)
/// - Issue not in active_jobs
/// - Assigned to the bot (or no bot_login configured)
pub fn is_candidate(
  item: types.ProjectItem,
  cfg: types.GitHubPickerConfig,
) -> Bool {
  let status_ok = item.status_name == cfg.todo_value
  let state_ok = string.uppercase(item.content.state) == "OPEN"
  let repo_ok =
    normalize_repo(item.content.repository) == normalize_repo(cfg.repo)
  let job_key = types.job_key_for_issue(item.content.number)
  let not_active = !list.contains(cfg.active_jobs, job_key)
  let assignee_ok = case cfg.bot_login {
    "" -> True
    login -> list.contains(item.content.assignee_logins, login)
  }
  status_ok && state_ok && repo_ok && not_active && assignee_ok
}

fn normalize_repo(r: String) -> String {
  // Port minimal normalize from bash jq (strip github urls, .git)
  r
  |> string.replace("https://github.com/", "")
  |> string.replace("http://github.com/", "")
  |> string.replace(".git", "")
  |> string.trim
}

/// Build list of candidates with computed priority_sort key
pub fn to_candidates(
  items: List(types.ProjectItem),
  cfg: types.GitHubPickerConfig,
) -> List(types.Candidate) {
  items
  |> list.filter(fn(item) { is_candidate(item, cfg) })
  |> list.map(fn(item) {
    let sort =
      compute_priority_sort(
        item.priority,
        cfg.priority_mode,
        cfg.priority_order,
      )
    types.Candidate(item: item, priority_sort: sort)
  })
}

/// Select the best candidate using sort key (priority desc), then updated_at asc (oldest), then lowest issue number.
pub fn select_best(
  candidates: List(types.Candidate),
) -> Result(types.ProjectItem, types.SelectionError) {
  case candidates {
    [] -> Error(types.NoMatchingIssue)
    _ -> {
      let sorted =
        list.sort(candidates, fn(a, b) {
          case int.compare(a.priority_sort, b.priority_sort) {
            order.Gt -> order.Gt
            order.Lt -> order.Lt
            order.Eq ->
              case
                string.compare(
                  a.item.content.updated_at,
                  b.item.content.updated_at,
                )
              {
                order.Gt -> order.Gt
                order.Lt -> order.Lt
                order.Eq ->
                  int.compare(a.item.content.number, b.item.content.number)
              }
          }
        })
      case sorted {
        [first, ..] -> Ok(first.item)
        _ -> Error(types.NoMatchingIssue)
      }
    }
  }
}

/// Main public API for the selector slice: pick the top SelectedGitHubIssue or NoMatchingIssue.
/// Follows exact filter+sort from bash jq in bin/worker-pick-issue.sh (including assignee to bot).
pub fn pick(
  items: List(types.ProjectItem),
  cfg: types.GitHubPickerConfig,
) -> Result(types.SelectedGitHubIssue, types.SelectionError) {
  let cands = to_candidates(items, cfg)
  case select_best(cands) {
    Ok(item) -> {
      // extract priority strings for emit (name for single_select, number str for number mode)
      let #(pname, pnum) = case item.priority {
        types.SingleSelectValue(n) -> #(n, "")
        types.NumberValue(n) -> #("", int.to_string(n))
        _ -> #("", "")
      }
      let slug =
        task_slug.task_slug_for_issue(item.content.number, item.content.title)
      Ok(types.selected_from_item(item, pname, pnum, slug))
    }
    Error(e) -> Error(e)
  }
}

/// Convenience: filter only (for tests / future)
pub fn filter_candidates(
  items: List(types.ProjectItem),
  cfg: types.GitHubPickerConfig,
) -> List(types.ProjectItem) {
  list.filter(items, fn(i) { is_candidate(i, cfg) })
}

/// Convenience: sort candidates by the priority rule (for tests / future)
pub fn sort_by_priority(
  candidates: List(types.Candidate),
) -> List(types.Candidate) {
  list.sort(candidates, fn(a, b) {
    case int.compare(a.priority_sort, b.priority_sort) {
      order.Gt -> order.Gt
      order.Lt -> order.Lt
      order.Eq ->
        case
          string.compare(a.item.content.updated_at, b.item.content.updated_at)
        {
          order.Gt -> order.Gt
          order.Lt -> order.Lt
          order.Eq -> int.compare(a.item.content.number, b.item.content.number)
        }
    }
  })
}
