pub type PullRequest {
  PullRequest(
    number: Int,
    title: String,
    author: String,
    head_ref: String,
    head_sha: String,
    base_ref: String,
    mergeable: Bool,
    conflicted: Bool,
    is_cross_repository: Bool,
  )
}

pub type ConflictFile {
  ConflictFile(path: String, our_content: String, their_content: String)
}

pub type ResolutionStrategy {
  Rebase
  Merge
}

pub type ResolutionResult {
  ResolutionSuccess(
    resolved_files: List(String),
    commit_sha: String,
    pushed: Bool,
  )
  ResolutionNoConflicts
  ResolutionFailed(error: String)
}

pub type WorktreeContext {
  WorktreeContext(
    pr_number: Int,
    worktree_path: String,
    branch_name: String,
    original_dir: String,
  )
}

pub type CodexResolution {
  CodexResolution(resolved_content: String, explanation: String)
  CodexSkipped(reason: String)
  CodexFailed(error: String)
}
