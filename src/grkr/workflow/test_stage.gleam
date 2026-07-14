import gleam/string

import grkr/workflow/ffi as wf

/// CLI entry for test stage hooks (thin; used by both GitHub and Linear providers).
/// Subcommands:
///   run-tests               Thin hook; full verification command execution (BUILD_COMMAND/TEST_COMMAND or npm test),
///                           result capture, .grkr/tasks/<slug>/test.md write, gh comment (GitHub) or Linear mutation plan stay in shell (bin/grkr).
///   completion-marker <slug> Prints the test checkpoint marker HTML comment (per spec/26 + 31).
///   help
/// Thin integration point per spec/parts/26-stage-5-test.md + spec/parts/39 item 9 (#18).
/// Mirrors implement_stage pattern exactly (small pure hooks only; no heavy logic here).
/// Heavy execution + write + provider mutation planning stay in shell per slice pattern.
/// No full test runner in Gleam (delegate to shell).
///
/// Public API for tests + shell delegates:
///   test_hook_message() -> message for run-tests hook
///   completion_marker(slug) -> "<!-- grkr:checkpoint stage=test task=<slug> version=1 -->"
pub fn main() {
  case wf.argv() {
    ["run-tests"] -> do_run_tests()
    ["completion-marker", slug] -> do_completion_marker(slug)
    ["help"] | [] -> emit_usage()
    _ -> emit_usage()
  }
}

fn emit_usage() {
  wf.console_error("Usage: gleam run -m grkr/workflow/test_stage -- run-tests")
  wf.console_error("       gleam run -m grkr/workflow/test_stage -- completion-marker <task-slug>")
  wf.console_error("       gleam run -m grkr/workflow/test_stage -- help")
  wf.console_error("")
  wf.console_error("Test stage hooks (thin, shared by providers) per spec/26 + spec/parts/39 item 9 (#18 / t_6d2b458b).")
  wf.console_error("Thin shell orchestrates test commands + checkpoint + gh/Linear mutation; this provides pure hooks.")
  wf.console_error("Heavy test execution + write + mutation planning delegated to shell per slice pattern.")
  wf.console_error("See ensure_test_checkpoint, ensure_linear_test_checkpoint, write_test_checkpoint_with_header, build_command_list in bin/grkr.")
  wf.console_error("Completion marker matches progress/checkpoint_id format for test stage.")
  wf.exit(2)
}

/// Pure hook message for test stage (per spec/26).
/// Used by CLI run-tests; shell keeps heavy cmd exec + .md write + gh post.
pub fn test_hook_message() -> String {
  "🧪 test_stage run-tests hook (delegated to shell per spec/26; exit 0)"
}

/// Pure hook for test checkpoint marker per spec/26 + spec/parts/31-test-checkpoint.md .
/// Used by shell delegates if needed (currently progress/cli marker test <slug> is canonical,
/// this provides dedicated test_stage surface mirroring implement_stage's commit-message hook).
pub fn completion_marker(task_slug: String) -> String {
  let clean = string.trim(task_slug)
  "<!-- grkr:checkpoint stage=test task=" <> clean <> " version=1 -->"
}

fn do_run_tests() {
  // Thin hook only. Real run + write + provider-specific planning (gh vs Linear dry-run) happen in shell.
  // Respects CURRENT_ISSUE_WORKTREE, env BUILD/TEST_COMMAND. Provider chosen via GRKR_ISSUE_PROVIDER / dispatch.
  wf.console_log(test_hook_message())
  wf.exit(0)
}

fn do_completion_marker(task_slug: String) {
  let marker = completion_marker(task_slug)
  wf.console_log(marker)
  wf.exit(0)
}
