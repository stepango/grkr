import gleam/list
import gleam/string
import gleam/result
import grkr/decision_gate/types

/// Parse a decision from Codex output
/// Returns the first non-empty line that is exactly "proceed" or "refuse" (case-insensitive)
pub fn parse_decision(output: String) -> Result(types.Decision, Nil) {
  output
  |> string.split("\n")
  |> list.filter(fn(line) { line != "" })
  |> list.map(string.trim)
  |> list.map(string.lowercase)
  |> list.find(fn(line) { line == "proceed" || line == "refuse" })
  |> result.map(fn(line) {
    case line {
      "proceed" -> types.Proceed
      "refuse" -> types.Refuse
      _ -> types.Refuse
    }
  })
}

/// Check if a decision string is valid
pub fn is_valid_decision(decision: String) -> Bool {
  let normalized = string.lowercase(string.trim(decision))
  normalized == "proceed" || normalized == "refuse"
}

/// Normalize a decision string to a Decision type
/// Defaults to Refuse for safety (fail-closed)
pub fn normalize_decision(decision: String) -> types.Decision {
  let normalized = string.lowercase(string.trim(decision))
  case normalized {
    "proceed" -> types.Proceed
    _ -> types.Refuse
  }
}

/// Convert a Decision to a string
pub fn decision_to_string(decision: types.Decision) -> String {
  case decision {
    types.Proceed -> "proceed"
    types.Refuse -> "refuse"
  }
}
