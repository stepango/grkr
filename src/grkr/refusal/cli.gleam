import gleam/int
import gleam/option.{None, Some}
import gleam/result
import gleam/string

import grkr/refusal/config
import grkr/refusal/flow
import grkr/refusal/linear_flow
import grkr/refusal/types.{
  type RefusalError, CheckpointFailed, FetchFailed, OtherError, ProjectMoveFailed,
  to_string,
}

@external(javascript, "../refusal/cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "console", "log")
fn console_log(s: String) -> Nil

@external(javascript, "console", "error")
fn console_error(s: String) -> Nil

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
  console_log("Usage: gleam run -m grkr/refusal/cli -- <issue-number-or-identifier> [refusal-class] [refusal-reasoning]")
  console_log("")
  console_log("Refusal CLI entrypoint (provider-aware):")
  console_log("  GRKR_ISSUE_PROVIDER=github (default): <issue-number> ...   (GitHub numeric)")
  console_log("  GRKR_ISSUE_PROVIDER=linear: <identifier> ...               (e.g. ENG-123)")
  console_log("  <issue> [class] [reason]   Execute refusal flow (checkpoint, progress, plan mutations)")
  console_log("  help                       Show this message")
  console_log("")
  console_log("Valid classes: underspecified too_large missing_dependency needs_design_decision unsafe_autonomous_change repo_not_ready other")
  console_log("Defaults: class=underspecified, reasoning=\"The issue does not appear ready for safe autonomous implementation...\"")
  console_log("Emits shell-compatible KEY=\"val\" lines on success for robot-main.sh / supervisor parsing.")
  console_log("Uses REFUSAL_* / ENABLE_* / TASKS_DIR / GRKR_ISSUE_PROVIDER from env.")
  console_log("GitHub: uses gh. Linear: uses issue_provider (fixture/live) + plans Linear mutations; no gh calls.")
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
  let provider = config.issue_provider_name()
  case provider {
    "linear" -> run_cli_linear(issue_str, class_raw, reasoning_raw)
    _ -> run_cli_github(issue_str, class_raw, reasoning_raw)
  }
}

fn run_cli_github(issue_str: String, class_raw: String, reasoning_raw: String) {
  console_error("📋 Fetching issue #" <> issue_str <> "...")
  case parse_issue_number(issue_str) {
    Error(msg) -> {
      emit_error("Invalid issue number: " <> msg)
      exit(1)
    }
    Ok(issue) -> {
      case flow.run_refusal(issue, class_raw, reasoning_raw) {
        Ok(res) -> {
          console_error("📝 Posting refusal checkpoint for issue #" <> issue_str <> "...")
          case res.moved_to_backlog {
            True -> console_error("📥 Moved issue #" <> issue_str <> " to Backlog.")
            False -> Nil
          }
          emit("REFUSAL_PROCESSED", "1")
          case res.issue_number {
            Some(n) -> emit("ISSUE_NUMBER", int.to_string(n))
            None -> Nil
          }
          emit("TASK_SLUG", res.task_slug)
          emit("REFUSAL_CLASS", to_string(res.class))
          emit("REFUSAL_COMMENT_ID", res.comment_id)
          emit("PROGRESS_FILE", res.progress_file)
          emit("PROVIDER", res.provider)
          console_error("⏸️ Refused implementation for issue #" <> issue_str <> ".")
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

fn run_cli_linear(issue_str: String, class_raw: String, reasoning_raw: String) {
  console_error("📋 Loading Linear issue " <> issue_str <> "...")
  case linear_flow.run_refusal_linear(issue_str, class_raw, reasoning_raw) {
    Ok(res) -> {
      console_error("📝 Planning refusal checkpoint for Linear " <> issue_str <> "...")
      // For Linear we plan mutations (no live gh backlog); always emit processed
      emit("REFUSAL_PROCESSED", "1")
      emit("PROVIDER", "linear")
      case res.issue_identifier {
        Some(id) -> emit("ISSUE_IDENTIFIER", id)
        None -> emit("ISSUE_IDENTIFIER", issue_str)
      }
      emit("TASK_SLUG", res.task_slug)
      emit("REFUSAL_CLASS", to_string(res.class))
      emit("REFUSAL_COMMENT_ID", res.comment_id)
      emit("PROGRESS_FILE", res.progress_file)
      console_error("⏸️ Refused implementation for Linear " <> issue_str <> ".")
      exit(0)
    }
    Error(e) -> {
      emit_error(refusal_error_to_string(e))
      exit(1)
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
