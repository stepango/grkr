import gleeunit
import gleeunit/should
import gleam/string
import grkr/workflow/worktree as wt

pub fn main() {
  gleeunit.main()
}

pub fn issue_worktree_dir_test() {
  // default (no GRKR_ROOT) uses "."
  let dir = wt.issue_worktree_dir("issue-42-my-feature")
  string.ends_with(dir, "/.grkr/worktrees/issue-42-my-feature") |> should.be_true()
  string.contains(dir, "issue-42-my-feature") |> should.be_true()
}

pub fn issue_worktree_base_ref_test() {
  // depends on MAIN_BRANCH env or defaults to "main" then checks
  let ref = wt.issue_worktree_base_ref()
  // should be one of main, origin/main, HEAD
  let is_valid = ref == "main" || ref == "origin/main" || ref == "HEAD" || string.contains(ref, "main")
  is_valid |> should.be_true()
}

pub fn worktree_types_smoke() {
  // ensure types reexported and module loads (compile time check)
  let _ = wt.issue_worktree_dir("x")
  Nil
}
