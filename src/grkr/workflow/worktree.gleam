
import grkr/workflow/ffi.{type ExecResult}
import grkr/workflow/worktree_ops as ops
import grkr/workflow/worktree_stage as stage
import grkr/workflow/worktree_types as types

/// Reexported types (moved to worktree_types.gleam per split in t_d704484d)
pub type WorktreeInfo = types.WorktreeInfo

pub type PrepareResult = types.PrepareResult

/// Reexports of issue worktree ops (moved to worktree_ops.gleam)
/// Preserves exact public API + parity for callers (main.gleam, bin sh via CLI, tests).
pub fn issue_worktree_dir(task_slug: String) -> String {
  ops.issue_worktree_dir(task_slug)
}

pub fn issue_worktree_ready(worktree_dir: String) -> Bool {
  ops.issue_worktree_ready(worktree_dir)
}

pub fn issue_worktree_base_ref() -> String {
  ops.issue_worktree_base_ref()
}

pub fn prepare_issue_worktree(branch: String, task_slug: String) -> Result(String, String) {
  ops.prepare_issue_worktree(branch, task_slug)
}

pub fn git_in_issue_context(args: List(String)) -> ExecResult {
  ops.git_in_issue_context(args)
}

pub fn cleanup_issue_worktree(worktree_dir: String) -> Result(Nil, String) {
  ops.cleanup_issue_worktree(worktree_dir)
}

/// Reexports of stage/collect ops (moved to worktree_stage.gleam)
pub fn collect_relevant_issue_paths() -> List(String) {
  stage.collect_relevant_issue_paths()
}

pub fn stage_relevant_issue_files() -> Nil {
  stage.stage_relevant_issue_files()
}
