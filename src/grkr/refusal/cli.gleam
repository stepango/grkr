import gleam/int
import gleam/result
import gleam/string

import grkr/refusal/flow
import grkr/refusal/types.{
  type RefusalError, CheckpointFailed, FetchFailed,
  OtherError, ProjectMoveFailed, to_string,
}

@external(javascript, "../refusal/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "console", "log")
fn console_log(s: String) -> Nil

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil

fn shell_quote(value: String) -> String {
  "\""
    <> {
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("$", "\\$")
    |> string.replace("`", "\\`")
  }
    <> "\""
}

fn emit(key: String, value: String) {
  console_log(key <> "=" <> shell_quote(value))
}

fn emit_error(msg: String) {
  console_log("ERROR=" <> shell_quote(msg))
}

/// CLI entrypoint for refusal (GitHub-only v2).
/// Mirrors github_picker/main + progress/cli patterns.
/// Default: run refusal for <issue> [class] [reasoning...]
/// Emits REFUSAL_PROCESSED=1 + vars (exact interface for thin shells/supervisor)
/// or ERROR= on failure. Delegates all logic to flow.run_refusal + assessment/checkpoint.
pub fn main() {
  let args = argv()
  case args {
    ["help"] -> emit_usage()
    [] -> emit_usage()
    _ -> run_from_args(args)
  }
}

fn emit_usage() {
  console_log("Usage: gleam run -m grkr/refusal/cli -- <issue-number> [refusal-class] [refusal-reasoning]")
  console_log("")
  console_log("Refusal CLI entrypoint (GitHub-only v2):")
  console_log("  <issue> [class] [reason]   Execute refusal flow (fetch, checkpoint, progress update, optional backlog move)")
  console_log("  help                       Show this message")
  console_log("")
  console_log("Valid classes: underspecified too_large missing_dependency needs_design_decision unsafe_autonomous_change repo_not_ready other")
  console_log("Defaults: class=underspecified, reasoning=\"The issue does not appear ready for safe autonomous implementation...\"")
  console_log("Emits shell-compatible KEY=\"val\" lines on success for robot-main.sh / supervisor parsing.")
  console_log("Uses REFUSAL_* / ENABLE_PROJECT_STATUS_UPDATES / TASKS_DIR etc from env (via refusal/config).")
  console_log("Supports test mocks via PATH (gh, etc). No fixture mode yet (real gh path).")
  exit(2)
}

fn run_from_args(args: List(String)) {
  case args {
    [issue_str] -> run_cli(issue_str, "", "")
    [issue_str, class_str] -> run_cli(issue_str, class_str, "")
    [issue_str, class_str, ..reason_parts] -> {
      let reasoning = string.join(reason_parts, " ")
      run_cli(issue_str, class_str, reasoning)
    }
    _ -> emit_usage()
  }
}

fn run_cli(issue_str: String, class_raw: String, reasoning_raw: String) {
  case parse_issue_number(issue_str) {
    Error(msg) -> {
      emit_error("Invalid issue number: " <> msg)
      exit(1)
    }
    Ok(issue) -> {
      case flow.run_refusal(issue, class_raw, reasoning_raw) {
        Ok(res) -> {
          emit("REFUSAL_PROCESSED", "1")
          emit("ISSUE_NUMBER", int.to_string(res.issue_number))
          emit("TASK_SLUG", res.task_slug)
          emit("REFUSAL_CLASS", to_string(res.class))
          emit("REFUSAL_COMMENT_ID", res.comment_id)
          emit("PROGRESS_FILE", res.progress_file)
          exit(0)
        }
        Error(e) -> {
          emit_error(refusal_error_to_string(e))
          exit(1)
        }
      }
    }
  }
}

fn parse_issue_number(s: String) -> Result(Int, String) {
  int.parse(s)
  |> result.map_error(fn(_) { s })
}

fn refusal_error_to_string(e: RefusalError) -> String {
  case e {
    OtherError(m) -> m
    FetchFailed(m) -> "fetch_failed: " <> m
    CheckpointFailed(m) -> "checkpoint_failed: " <> m
    ProjectMoveFailed(m) -> "project_move_failed: " <> m
  }
}
