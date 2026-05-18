import gleam/int
import gleam/list
import gleam/result
import gleam/string

import grkr/github_picker/types.{
  type PriorityMode, type PriorityValue, NoPriority, Number, NumberValue,
  SingleSelect, SingleSelectValue,
}

/// Compute numeric sort key for priority (lower number = higher urgency, comes first in sort)
/// Extracted to keep selector.gleam small.
pub fn compute_priority_sort(
  prio: PriorityValue,
  mode: PriorityMode,
  order: List(String),
) -> Int {
  case mode {
    Number ->
      case prio {
        NumberValue(n) -> 0 - n
        _ -> 0
      }
    SingleSelect ->
      case prio {
        SingleSelectValue(name) -> index_of(order, name)
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

/// Parse PRIORITY_MODE env (or detected) to internal mode. Defaults to SingleSelect.
/// Matches bash normalize_priority_mode + detection.
pub fn priority_mode_from_string(value: String) -> PriorityMode {
  let lower = string.lowercase(string.trim(value))
  case string.contains(lower, "number") {
    True -> Number
    False ->
      case string.contains(lower, "select") {
        True -> SingleSelect
        False -> SingleSelect
      }
  }
}

/// Normalize for comparison (used in config load to match bash normalize_priority_mode)
pub fn normalize_priority_mode(value: String) -> String {
  let lower = string.lowercase(value)
  case
    string.contains(lower, "number"),
    string.contains(lower, "select")
  {
    True, _ -> "number"
    _, True -> "single_select"
    _, _ -> ""
  }
}
