import gleam/int
import gleam/string
import grkr/decision_gate/types

/// Build a decision prompt from context
pub fn build_decision_prompt(context: types.DecisionGateContext) -> String {
  let issue = context.issue
  let repo = context.repo

  string.join(
    [
      "Decide whether the GitHub issue below should proceed to implementation now.\n",
      "Reply with exactly one word on the first non-empty line: proceed or refuse.\n",
      "Only reply with proceed when the issue is sufficiently specified, bounded, and ready for one autonomous implementation pass.\n",
      "If you choose refuse:\n",
      "- Put one refusal class on the second non-empty line.\n",
      "- Put a short explanation after that.\n",
      "Allowed refusal classes: underspecified, too_large, missing_dependency, needs_design_decision, unsafe_autonomous_change, repo_not_ready, other.\n",
      "",
      "**Issue #" <> int_to_string(issue.issue_number) <> ": " <> issue.title <> "**",
      "**URL:** " <> issue.url,
      "",
      "**Description:**",
      issue.body,
      "",
      "**Checkpoint files:**",
      "- " <> repo.root <> "/.grkr/tasks/" <> repo.task_slug <> "/research.md",
      "- " <> repo.root <> "/.grkr/tasks/" <> repo.task_slug <> "/plan.md",
      "",
      "**Repository context:**",
      "- Issue worktree: " <> repo.worktree_dir,
      "- Repository root: " <> repo.root,
      "- Main repo policy: keep changed files at " <> int_to_string(repo.max_file_lines) <> " lines or fewer.",
      "",
    ],
    "\n",
  )
}

/// Build a refusal checkpoint markdown file
pub fn build_refusal_checkpoint(
  issue: types.IssueContext,
  repo: types.RepoContext,
  refusal: types.RefusalDetails,
  summary: String,
) -> String {
  string.join(
    [
      "<!-- grkr:checkpoint stage=refusal task=" <> repo.task_slug <> " version=1 -->",
      "",
      "## Implementation refused",
      "",
      "Issue #" <> int_to_string(issue.issue_number) <> ": " <> issue.title,
      "",
      "### Refusal summary",
      "",
      summary,
      "",
      "### Reason class",
      "",
      refusal_class_to_string(refusal.class),
      "",
      "### Detailed reasoning",
      "",
      refusal.reasoning,
      "",
      "### What is needed before implementation",
      "",
      missing_requirements(refusal.class),
      "",
      "### Suggested next actions",
      "",
      next_steps(refusal.class),
      "",
      "### Should the issue be split?",
      "",
      split_recommendation(refusal.class),
      "",
      "### Are follow-up issues recommended?",
      "",
      follow_up_recommendation(refusal.class),
    ],
    "\n",
  )
}

fn int_to_string(i: Int) -> String {
  int.to_string(i)
}

fn refusal_class_to_string(class: types.RefusalClass) -> String {
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

fn missing_requirements(class: types.RefusalClass) -> String {
  case class {
    types.Underspecified -> {
      "- Explicit acceptance criteria or expected behavior examples
- Clear success conditions for the implementation and test stages"
    }
    types.TooLarge -> {
      "- A smaller, explicitly scoped first slice of work
- A concrete split between independent follow-up issues"
    }
    types.MissingDependency -> {
      "- The missing upstream dependency, API, or prerequisite issue
- Confirmation that the dependency is available in the target branch"
    }
    types.NeedsDesignDecision -> {
      "- A concrete design or product decision for the ambiguous behavior
- Confirmation of the preferred implementation direction"
    }
    types.UnsafeAutonomousChange -> {
      "- Human review for the risky change path
- A safer bounded approach or rollback strategy"
    }
    types.RepoNotReady -> {
      "- Repository health restored enough for issue-local changes to be validated
- Confirmation that unrelated build or test failures are resolved"
    }
    types.Other -> {
      "- The missing prerequisite identified in the refusal reasoning above
- A narrower, directly testable issue scope"
    }
  }
}

fn next_steps(class: types.RefusalClass) -> String {
  case class {
    types.TooLarge -> {
      "- Split the issue into smaller independently testable tasks
- Re-run the workflow against the first bounded slice"
    }
    _ -> {
      "- Update the issue with the missing detail identified above
- Re-run the workflow after the issue is clarified and bounded"
    }
  }
}

fn split_recommendation(class: types.RefusalClass) -> String {
  case class {
    types.TooLarge -> {
      "Yes. The current issue is too broad for one safe autonomous change."
    }
    types.UnsafeAutonomousChange -> {
      "Yes. The current issue is too broad for one safe autonomous change."
    }
    _ -> {
      "No immediate split is required if the missing prerequisite can be resolved directly in this issue."
    }
  }
}

fn follow_up_recommendation(class: types.RefusalClass) -> String {
  case class {
    types.TooLarge -> {
      "Yes. Follow-up issues are recommended to separate prerequisite or decision work."
    }
    types.MissingDependency -> {
      "Yes. Follow-up issues are recommended to separate prerequisite or decision work."
    }
    types.NeedsDesignDecision -> {
      "Yes. Follow-up issues are recommended to separate prerequisite or decision work."
    }
    _ -> {
      "Not necessarily. The current issue may proceed once the missing information is added."
    }
  }
}
