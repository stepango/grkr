import gleam/string

import grkr/workflow/ffi as wf

/// CLI entry for implement stage hooks (GitHub-only v2).
/// Subcommands:
///   commit-message <issue> <title>   Prints conventional commit msg per spec/25 (feat(robot): ...)
///   help
/// Thin integration point; codex run + prompt write + heavy logic stay in thin shell (bin/grkr).
/// Mirrors research/plan checkpoint patterns (Gleam core + thin sh delegate in grkr-issue-workflow.sh + bin/grkr callsites).
/// One small deliverable per task spec (t_39ab1e08 / #17 / spec/parts/39 item 8).
///
/// Public API for tests + shell delegates:
///   generate_commit_message(issue, title) -> "feat(robot): implement #<issue> <cleaned title>"
pub fn main() {
  case wf.argv() {
    ["commit-message", issue, title] -> do_commit_message(issue, title)
    ["help"] | [] -> emit_usage()
    _ -> emit_usage()
  }
}

fn emit_usage() {
  wf.console_error("Usage: gleam run -m grkr/workflow/implement_stage -- commit-message <issue> <title>")
  wf.console_error("       gleam run -m grkr/workflow/implement_stage -- help")
  wf.console_error("")
  wf.console_error("Implement stage hooks (GitHub-only v2) per spec/25 + spec/parts/39 item 8 (#17).")
  wf.console_error("Thin shell orchestrates codex/publish; this provides pure hooks (e.g. commit msg).")
  wf.console_error("No LLM/codex invocation here (stays shell-orchestrated per slice patterns).")
  wf.exit(2)
}

/// Pure hook for conventional commit message per spec/25.
/// Used by bin/grkr via thin delegate in grkr-issue-workflow.sh
pub fn generate_commit_message(issue: String, title: String) -> String {
  let clean_title = string.trim(title)
  "feat(robot): implement #" <> issue <> " " <> clean_title
}

fn do_commit_message(issue: String, title: String) {
  let msg = generate_commit_message(issue, title)
  wf.console_log(msg)
  wf.exit(0)
}
