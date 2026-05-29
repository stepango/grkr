import grkr/workflow/ffi as wf

/// CLI entry for test stage hooks (GitHub-only v2).
/// Subcommands:
///   run-tests   Thin hook; full verification command execution (BUILD_COMMAND/TEST_COMMAND or npm test),
///               result capture, .grkr/tasks/<slug>/test.md write, gh comment post stay in shell (bin/grkr).
///   help
/// Thin integration point per spec/parts/26-stage-5-test.md + spec/parts/39 item 9 (#18).
/// Mirrors implement_stage pattern exactly (small pure hooks only; no heavy logic here).
/// No full test runner in Gleam for this slice (delegate to shell per card).
/// One small deliverable per task spec (t_d87d2215 / #18 / spec/parts/39 item 9).
///
/// Public API for tests + shell delegates:
///   (run-tests hook; future pure fns e.g. for command formatting / recommendation)
pub fn main() {
  case wf.argv() {
    ["run-tests"] -> do_run_tests()
    ["help"] | [] -> emit_usage()
    _ -> emit_usage()
  }
}

fn emit_usage() {
  wf.console_error("Usage: gleam run -m grkr/workflow/test_stage -- run-tests")
  wf.console_error("       gleam run -m grkr/workflow/test_stage -- help")
  wf.console_error("")
  wf.console_error("Test stage hooks (GitHub-only v2) per spec/26 + spec/parts/39 item 9 (#18 / t_d87d2215).")
  wf.console_error("Thin shell orchestrates test commands + checkpoint + gh post; this provides pure hooks.")
  wf.console_error("Heavy test execution (npm test etc) delegated to shell per slice pattern (no full npm here).")
  wf.console_error("See ensure_test_checkpoint + write_test_checkpoint_file + build_command_list in bin/grkr.")
  wf.exit(2)
}

/// Pure hook message for test stage (per spec/26).
/// Used by CLI run-tests; shell keeps heavy cmd exec + .md write + gh post.
pub fn test_hook_message() -> String {
  "🧪 test_stage run-tests hook (delegated to shell per spec/26; exit 0)"
}

fn do_run_tests() {
  // Thin hook only. Real run happens in shell context (respects CURRENT_ISSUE_WORKTREE, env BUILD/TEST_COMMAND).
  // This allows future expansion (e.g. Gleam-side command list gen) without changing sh call sites.
  wf.console_log(test_hook_message())
  wf.exit(0)
}
