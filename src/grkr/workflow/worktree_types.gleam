/// Types for worktree model (per spec/12-worktree-model.md)
/// GitHub-only v2. Small module per AGENTS + t_d704484d split.

pub type WorktreeInfo {
  WorktreeInfo(dir: String, branch: String, task_slug: String)
}

pub type PrepareResult {
  PrepareResult(dir: String, reused: Bool)
}
