/// The possible decisions from the decision gate
pub type Decision {
  Proceed
  Refuse
}

/// Valid refusal classes
pub type RefusalClass {
  Underspecified
  TooLarge
  MissingDependency
  NeedsDesignDecision
  UnsafeAutonomousChange
  RepoNotReady
  Other
}

/// Parsed refusal details
pub type RefusalDetails {
  RefusalDetails(
    class: RefusalClass,
    reasoning: String,
  )
}

/// Decision gate result
pub type DecisionResult {
  DecisionProceeded
  DecisionRefused(RefusalDetails)
}

/// Issue context for decision prompt
pub type IssueContext {
  IssueContext(
    issue_number: Int,
    title: String,
    url: String,
    body: String,
  )
}

/// Repository context for decision prompt
pub type RepoContext {
  RepoContext(
    root: String,
    worktree_dir: String,
    task_slug: String,
    max_file_lines: Int,
  )
}

/// Full context for the decision gate
pub type DecisionGateContext {
  DecisionGateContext(
    issue: IssueContext,
    repo: RepoContext,
  )
}
