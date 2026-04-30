import gleam/list
import gleam/string
import grkr/decision_gate/types

/// Parse refusal details from Codex output
/// Extracts the refusal class (line after "refuse") and reasoning
pub fn parse_refusal_details(output: String) -> Result(types.RefusalDetails, Nil) {
  let lines =
    output
    |> string.split("\n")
    |> list.map(string.trim)

  // Check if "refuse" exists in the output
  let has_refuse =
    list.any(lines, fn(line) {
      let lower = string.lowercase(line)
      lower == "refuse"
    })

  case has_refuse {
    False -> Error(Nil)
    True -> {
      // Find "refuse" and get everything after it
      let after_refuse = get_after_refuse(lines, [])

      // Filter out empty lines to find the class
      let non_empty = list.filter(after_refuse, fn(line) { line != "" })

      case non_empty {
        [class_line, ..reasoning_lines] -> {
          case is_valid_refusal_class(class_line) {
            True -> {
              let reasoning =
                reasoning_lines
                |> list.map(string.trim)
                |> list.filter(fn(line) { line != "" })
                |> string.join("\n")

              Ok(types.RefusalDetails(class: normalize_refusal_class(class_line), reasoning: reasoning))
            }
            False -> {
              let reasoning =
                non_empty
                |> list.map(string.trim)
                |> list.filter(fn(line) { line != "" })
                |> string.join("\n")

              Ok(types.RefusalDetails(class: types.Other, reasoning: reasoning))
            }
          }
        }
        _ -> {
          // No class found, use default
          Ok(types.RefusalDetails(
            class: types.Other,
            reasoning: default_refusal_reasoning(),
          ))
        }
      }
    }
  }
}

/// Helper function to get all lines after "refuse"
fn get_after_refuse(lines: List(String), acc: List(String)) -> List(String) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] -> {
      let lower = string.lowercase(line)
      case lower {
        "refuse" -> rest
        _ -> get_after_refuse(rest, [line, ..acc])
      }
    }
  }
}

/// Normalize a refusal class string to a RefusalClass type
/// Defaults to Other for unknown classes (fail-closed)
pub fn normalize_refusal_class(class: String) -> types.RefusalClass {
  let normalized =
    class
    |> string.lowercase
    |> string.replace("-", "_")
    |> string.replace(" ", "_")

  case normalized {
    "underspecified" -> types.Underspecified
    "too_large" -> types.TooLarge
    "missing_dependency" -> types.MissingDependency
    "needs_design_decision" -> types.NeedsDesignDecision
    "unsafe_autonomous_change" -> types.UnsafeAutonomousChange
    "repo_not_ready" -> types.RepoNotReady
    "other" -> types.Other
    _ -> types.Other
  }
}

/// Check if a refusal class string is valid
pub fn is_valid_refusal_class(class: String) -> Bool {
  let normalized = normalize_refusal_class(class)
  case normalized {
    types.Other -> {
      // Only Other if the input was actually "other" or similar
      let lower = string.lowercase(string.trim(class))
      lower == "other"
    }
    _ -> True
  }
}

/// Default refusal reasoning when none is provided
pub fn default_refusal_reasoning() -> String {
  "The issue does not appear ready for safe autonomous implementation in its current state."
}

/// Generate the "what is needed before implementation" markdown for a refusal class
pub fn missing_requirements(class: types.RefusalClass) -> String {
  case class {
    types.Underspecified ->
      "- Explicit acceptance criteria or expected behavior examples
- Clear success conditions for the implementation and test stages"
    types.TooLarge ->
      "- A smaller, explicitly scoped first slice of work
- A concrete split between independent follow-up issues"
    types.MissingDependency ->
      "- The missing upstream dependency, API, or prerequisite issue
- Confirmation that the dependency is available in the target branch"
    types.NeedsDesignDecision ->
      "- A concrete design or product decision for the ambiguous behavior
- Confirmation of the preferred implementation direction"
    types.UnsafeAutonomousChange ->
      "- Human review for the risky change path
- A safer bounded approach or rollback strategy"
    types.RepoNotReady ->
      "- Repository health restored enough for issue-local changes to be validated
- Confirmation that unrelated build or test failures are resolved"
    types.Other ->
      "- The missing prerequisite identified in the refusal reasoning above
- A narrower, directly testable issue scope"
  }
}

/// Generate the suggested next actions markdown for a refusal class
pub fn next_steps(class: types.RefusalClass) -> String {
  case class {
    types.TooLarge ->
      "- Split the issue into smaller independently testable tasks
- Re-run the workflow against the first bounded slice"
    _ ->
      "- Update the issue with the missing detail identified above
- Re-run the workflow after the issue is clarified and bounded"
  }
}

/// Generate the split recommendation for a refusal class
pub fn split_recommendation(class: types.RefusalClass) -> String {
  case class {
    types.TooLarge ->
      "Yes. The current issue is too broad for one safe autonomous change."
    types.UnsafeAutonomousChange ->
      "Yes. The current issue is too broad for one safe autonomous change."
    _ ->
      "No immediate split is required if the missing prerequisite can be resolved directly in this issue."
  }
}

/// Generate the follow-up recommendation for a refusal class
pub fn follow_up_recommendation(class: types.RefusalClass) -> String {
  case class {
    types.TooLarge ->
      "Yes. Follow-up issues are recommended to separate prerequisite or decision work."
    types.MissingDependency ->
      "Yes. Follow-up issues are recommended to separate prerequisite or decision work."
    types.NeedsDesignDecision ->
      "Yes. Follow-up issues are recommended to separate prerequisite or decision work."
    _ ->
      "Not necessarily. The current issue may proceed once the missing information is added."
  }
}

/// Parse an implementation-to-refusal marker from Codex implementation output.
pub fn parse_implementation_refusal(output: String) -> Result(types.RefusalDetails, Nil) {
  let lines =
    output
    |> string.split("\n")
    |> list.map(string.trim)

  case lines_after_marker(lines) {
    [] -> Error(Nil)
    marker_lines -> parse_refusal_marker_lines(marker_lines)
  }
}

fn lines_after_marker(lines: List(String)) -> List(String) {
  case lines {
    [] -> []
    [line, ..rest] -> {
      case string.lowercase(line) == "grkr-refuse-implementation" {
        True -> rest
        False -> lines_after_marker(rest)
      }
    }
  }
}

fn parse_refusal_marker_lines(lines: List(String)) -> Result(types.RefusalDetails, Nil) {
  case first_non_empty(lines) {
    Ok(#(class_line, rest)) -> {
      case is_valid_refusal_class(class_line) {
        True -> {
          let reasoning =
            rest
            |> list.map(string.trim)
            |> list.filter(fn(line) { line != "" && line != "---" })
            |> string.join("\n")

          let final_reasoning = case reasoning {
            "" -> "Implementation discovered that the issue is not ready for safe autonomous completion."
            _ -> reasoning
          }

          Ok(types.RefusalDetails(
            class: normalize_refusal_class(class_line),
            reasoning: final_reasoning,
          ))
        }
        False -> Error(Nil)
      }
    }
    Error(_) -> Error(Nil)
  }
}

fn first_non_empty(lines: List(String)) -> Result(#(String, List(String)), Nil) {
  case lines {
    [] -> Error(Nil)
    [line, ..rest] -> {
      case line == "" {
        True -> first_non_empty(rest)
        False -> Ok(#(line, rest))
      }
    }
  }
}

/// Convert a RefusalClass to a string
pub fn refusal_class_to_string(class: types.RefusalClass) -> String {
  case class {
    types.Underspecified -> "underspecified"
    types.TooLarge -> "too_large"
    types.MissingDependency -> "missing_dependency"
    types.NeedsDesignDecision -> "needs_design_decision"
    types.UnsafeAutonomousChange -> "unsafe_autonomous_change"
    types.RepoNotReady -> "repo_not_ready"
    types.Other -> "other"
  }
}
