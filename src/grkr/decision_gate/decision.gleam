import gleam/list
import gleam/string
import grkr/decision_gate/types

/// Parse a decision from Codex output.
/// The first non-empty trimmed line must be exactly "proceed" or "refuse"
/// (case-insensitive). Later valid-looking lines are ignored so malformed
/// Codex output fails closed instead of explaining first and proceeding later.
pub fn parse_decision(output: String) -> Result(types.Decision, Nil) {
  case first_meaningful_line(output) {
    Ok(line) -> result_from_decision_line(line)
    Error(Nil) -> Error(Nil)
  }
}

fn first_meaningful_line(output: String) -> Result(String, Nil) {
  output
  |> string.split("\n")
  |> list.map(string.trim)
  |> list.find(fn(line) { line != "" })
}

fn result_from_decision_line(line: String) -> Result(types.Decision, Nil) {
  case string.lowercase(line) {
    "proceed" -> Ok(types.Proceed)
    "refuse" -> Ok(types.Refuse)
    _ -> Error(Nil)
  }
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
