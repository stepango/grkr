import gleam/list
import gleam/string

/// Refusal class enum matching the 7 classes from spec and bash
pub type RefusalClass {
  Underspecified
  TooLarge
  MissingDependency
  NeedsDesignDecision
  UnsafeAutonomousChange
  RepoNotReady
  Other(String)
}

/// Error variants for refusal flow
pub type RefusalError {
  OtherError(String)
  ProjectMoveFailed(String)
  FetchFailed(String)
  CheckpointFailed(String)
}

/// Result of running refusal flow
pub type RefusalResult {
  RefusalResult(
    issue_number: Int,
    task_slug: String,
    class: RefusalClass,
    comment_id: String,
    progress_file: String,
    moved_to_backlog: Bool,
  )
}

/// Config loaded at runtime for refusal (GitHub only for now)
pub type RefusalConfig {
  RefusalConfig(
    repo: String,
    tasks_dir: String,
    updates_enabled: Bool,
    requires_backlog: Bool,
    backlog_value: String,
    project_number: Int,
    project_owner: String,
    status_field_name: String,
  )
}

/// Implementation decision from Codex or decision gate
pub type ImplementationDecision {
  Proceed
  Refuse(RefusalClass, String)
}

/// Normalize input string to valid class (ports bash normalize_refusal_class_candidate + valid)
pub fn normalize_refusal_class(s: String) -> RefusalClass {
  let candidate = normalize_candidate(s)
  case candidate {
    "underspecified" -> Underspecified
    "too_large" -> TooLarge
    "missing_dependency" -> MissingDependency
    "needs_design_decision" -> NeedsDesignDecision
    "unsafe_autonomous_change" -> UnsafeAutonomousChange
    "repo_not_ready" -> RepoNotReady
    "other" -> Other("other")
    _ ->
      case candidate {
        "" -> Other("")
        _ -> Other(candidate)
      }
  }
}

fn normalize_candidate(s: String) -> String {
  let lower = string.lowercase(s)
  let with_unders =
    lower
    |> string.replace(" ", "_")
    |> string.replace("-", "_")
  let allowed = "abcdefghijklmnopqrstuvwxyz0123456789_"
  with_unders
  |> string.to_graphemes
  |> list.filter(fn(g) { string.contains(allowed, g) })
  |> string.concat
}

/// Strict from_string only for known classes (errors on invalid, unlike normalize which falls to Other)
pub fn from_string(s: String) -> Result(RefusalClass, String) {
  let candidate = normalize_candidate(s)
  case candidate {
    "underspecified" -> Ok(Underspecified)
    "too_large" -> Ok(TooLarge)
    "missing_dependency" -> Ok(MissingDependency)
    "needs_design_decision" -> Ok(NeedsDesignDecision)
    "unsafe_autonomous_change" -> Ok(UnsafeAutonomousChange)
    "repo_not_ready" -> Ok(RepoNotReady)
    "other" -> Ok(Other("other"))
    _ -> Error("invalid refusal class: " <> s)
  }
}

pub fn to_string(class: RefusalClass) -> String {
  case class {
    Underspecified -> "underspecified"
    TooLarge -> "too_large"
    MissingDependency -> "missing_dependency"
    NeedsDesignDecision -> "needs_design_decision"
    UnsafeAutonomousChange -> "unsafe_autonomous_change"
    RepoNotReady -> "repo_not_ready"
    Other(s) -> s
  }
}

pub fn to_display_name(class: RefusalClass) -> String {
  case class {
    Underspecified -> "underspecified (acceptance criteria unclear)"
    TooLarge -> "too_large (issue too broad for safe autonomous change)"
    MissingDependency -> "missing_dependency (upstream prerequisite missing)"
    NeedsDesignDecision -> "needs_design_decision (design/product decision required)"
    UnsafeAutonomousChange -> "unsafe_autonomous_change (risky change path)"
    RepoNotReady -> "repo_not_ready (repo health / build issues)"
    Other(s) -> "other: " <> s
  }
}

pub fn default_class() -> RefusalClass {
  Underspecified
}

/// Parse free text decision from Codex output or prompt (ports bash logic)
/// "proceed ..." -> Proceed
/// "refuse\n<class>\n<reason...>" -> Refuse(normalized class, reason)
pub fn parse_implementation_decision(input: String) -> ImplementationDecision {
  let trimmed = string.trim(input)
  let lines = string.split(trimmed, "\n")
  case lines {
    [] -> Proceed
    [first, ..rest] -> {
      let first_lower = string.lowercase(string.trim(first))
      case string.starts_with(first_lower, "proceed") {
        True -> Proceed
        False ->
          case string.starts_with(first_lower, "refuse") {
            True ->
              case rest {
                [] -> Refuse(Other("unspecified"), "")
                [class_line, ..reason_rest] -> {
                  let class_str = string.trim(class_line)
                  let class = normalize_refusal_class(class_str)
                  let reason =
                    reason_rest
                    |> string.join("\n")
                    |> string.trim
                  Refuse(class, reason)
                }
              }
            False -> {
              // fallback treat whole as other reason?
              Refuse(Other(string.trim(first)), string.join(rest, "\n") |> string.trim)
            }
          }
      }
    }
  }
}
