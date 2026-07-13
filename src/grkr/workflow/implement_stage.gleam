import gleam/string

import grkr/workflow/ffi as wf

/// CLI entry for implement stage hooks (provider-aware).
/// Subcommands:
///   commit-message <issue> <title>                     GitHub form: feat(robot): implement #N title
///   commit-message --provider linear <id> <title>      Linear form:  feat(robot): implement ENG-123 title (no #)
///   help
/// Thin integration point; codex run + prompt write + heavy logic stay in thin shell (bin/grkr).
/// Mirrors research/plan checkpoint patterns (Gleam core + thin sh delegate in grkr-issue-workflow.sh + bin/grkr callsites).
/// Extended for Linear implement stage (dry-run) per design-linear-implement-stage.md.
/// Public API for tests + shell delegates:
///   generate_commit_message(issue, title) -> GitHub style
///   generate_linear_commit_message(id, title) -> Linear style (no #)
pub fn main() {
  case wf.argv() {
    ["commit-message", "--provider", "linear", id, title] -> do_commit_message_linear(id, title)
    ["commit-message", issue, title] -> do_commit_message(issue, title)
    ["help"] | [] -> emit_usage()
    _ -> emit_usage()
  }
}

fn emit_usage() {
  wf.console_error("Usage: gleam run -m grkr/workflow/implement_stage -- commit-message <issue> <title>")
  wf.console_error("       gleam run -m grkr/workflow/implement_stage -- commit-message --provider linear <id> <title>")
  wf.console_error("       gleam run -m grkr/workflow/implement_stage -- help")
  wf.console_error("")
  wf.console_error("Implement stage hooks (provider-aware) per spec/25 + Linear implement slice.")
  wf.console_error("GitHub default keeps #N; Linear omits # per product decision.")
  wf.console_error("Thin shell orchestrates codex/publish; this provides pure hooks (e.g. commit msg).")
  wf.exit(2)
}

/// Pure hook for conventional commit message per spec/25 (GitHub).
/// Used by bin/grkr via thin delegate in grkr-issue-workflow.sh
pub fn generate_commit_message(issue: String, title: String) -> String {
  let clean_title = string.trim(title)
  "feat(robot): implement #" <> issue <> " " <> clean_title
}

/// Pure hook for Linear commit message (no # prefix on identifier).
/// Used by Linear implement path in bin/lib/linear_issue.sh (via delegate).
pub fn generate_linear_commit_message(id: String, title: String) -> String {
  let clean_title = string.trim(title)
  "feat(robot): implement " <> id <> " " <> clean_title
}

fn do_commit_message(issue: String, title: String) {
  let msg = generate_commit_message(issue, title)
  wf.console_log(msg)
  wf.exit(0)
}

fn do_commit_message_linear(id: String, title: String) {
  let msg = generate_linear_commit_message(id, title)
  wf.console_log(msg)
  wf.exit(0)
}
