import gleam/int
import gleam/string

import grkr/refusal/config
import grkr/refusal/flow
import grkr/refusal/linear_flow
import grkr/refusal/types.{
  type RefusalError, type RefusalResult, OtherError, CheckpointFailed, FetchFailed,
  ProjectMoveFailed,
}
import grkr/workflow/decision as dec
import grkr/workflow/ffi as wf

/// CLI entry for decision gate (provider-aware: github default; linear via GRKR_ISSUE_PROVIDER).
/// Subcommands:
///   run <issue> <decision-output-file> <progress.json> <task-slug> <worktree-dir> <decision-prompt-file>
///     Extract decision, update progress; on refuse call refusal/flow (github) or linear_flow.
///     print "proceed" or "refuse" for shell capture, exit 0/1.
pub fn main() {
  case wf.argv() {
    ["run", issue_str, output_file, progress_file, _slug, _worktree, _prompt] ->
      do_run_gate(issue_str, output_file, progress_file)
    ["help"] | [] -> emit_usage()
    _ -> emit_usage()
  }
}

fn emit_usage() {
  wf.console_error("Usage: gleam run -m grkr/workflow/decision_gate -- run <issue> <decision-output-file> <progress.json> <task-slug> <worktree> <prompt-file>")
  wf.console_error("       gleam run -m grkr/workflow/decision_gate -- help")
  wf.console_error("")
  wf.console_error("Decision gate (provider-aware): post-codex implement-or-refuse per spec/22.")
  wf.console_error("  GRKR_ISSUE_PROVIDER=github (default): <issue> is numeric GitHub #")
  wf.console_error("  GRKR_ISSUE_PROVIDER=linear: <issue> is identifier e.g. ENG-123")
  wf.console_error("Reuses decision parsing + refusal/flow (github) or linear_flow (linear) for refuse path.")
  wf.console_error("Prints 'proceed' or 'refuse' to stdout for capture; side effects on progress/checkpoint.")
  wf.console_error("GitHub default path is regression-green; Linear uses state/checkpoint helpers + planned mutations.")
  wf.exit(2)
}

fn do_run_gate(issue_str: String, output_file: String, progress_file: String) {
  case dec_extract_decision(output_file) {
    Error(e) -> {
      wf.console_error("❌ decision gate read/extract failed: " <> e)
      wf.exit(1)
    }
    Ok(decision) -> {
      case decision {
        "proceed" | "refuse" -> {
          case dec_update_progress(progress_file, decision) {
            Error(e) -> {
              wf.console_error("❌ update progress failed: " <> e)
              wf.exit(1)
            }
            Ok(_) -> {
              case decision {
                "proceed" -> {
                  wf.console_log("proceed")
                  wf.console_error("✅ Decision gate: proceed for " <> issue_label(issue_str))
                  wf.exit(0)
                }
                "refuse" -> {
                  // parse refusal details from output for flow
                  case parse_refusal_details(output_file) {
                    Ok(#(class, reason)) -> {
                      case invoke_refusal_flow(issue_str, class, reason) {
                        Ok(res) -> {
                          wf.console_error(
                            "📝 Posting refusal checkpoint for "
                            <> issue_label(issue_str)
                            <> "...",
                          )
                          case res.moved_to_backlog {
                            True ->
                              wf.console_error(
                                "📥 Moved " <> issue_label(issue_str) <> " to Backlog.",
                              )
                            False -> Nil
                          }
                          wf.console_error(
                            "⏸️ Refused implementation for "
                            <> issue_label(issue_str)
                            <> ".",
                          )
                          wf.console_log("refuse")
                          wf.console_error(
                            "⏸️ Decision gate: refused "
                            <> issue_label(issue_str)
                            <> " (class: "
                            <> class
                            <> ")",
                          )
                          wf.exit(0)
                        }
                        Error(e) -> {
                          wf.console_error("❌ refusal flow failed: " <> e)
                          wf.exit(1)
                        }
                      }
                    }
                    Error(e) -> {
                      wf.console_error("❌ parse refusal details: " <> e)
                      wf.exit(1)
                    }
                  }
                }
                _ -> {
                  wf.console_error("❌ unexpected decision after update")
                  wf.exit(1)
                }
              }
            }
          }
        }
        _ -> {
          wf.console_error(
            "❌ Decision gate for "
            <> issue_label(issue_str)
            <> " returned invalid: "
            <> decision,
          )
          wf.exit(1)
        }
      }
    }
  }
}

/// GitHub regression messages use "issue #N"; Linear uses "issue IDENT".
fn issue_label(issue_str: String) -> String {
  case config.issue_provider_name() {
    "linear" -> "issue " <> issue_str
    _ -> "issue #" <> issue_str
  }
}

fn dec_extract_decision(output_file: String) -> Result(String, String) {
  // reuse the decision module's file read + extract (exact parity)
  case wf_read_file(output_file) {
    Ok(content) -> {
      let d = dec.extract_decision_from_output(content)
      case d {
        "" -> Error("No proceed/refuse in " <> output_file)
        _ -> Ok(d)
      }
    }
    Error(e) -> Error("read " <> output_file <> ": " <> e)
  }
}

fn wf_read_file(path: String) -> Result(String, String) {
  wf.tl_read_text(path)
}

fn dec_update_progress(progress_file: String, decision: String) -> Result(Nil, String) {
  dec.update_task_progress_decision(progress_file, decision)
}

fn parse_refusal_details(output_file: String) -> Result(#(String, String), String) {
  case wf_read_file(output_file) {
    Ok(content) -> {
      let parsed = dec.parse_refusal_decision_output(content)
      // parsed is "class\n---\nreason" or "other\n---\n"
      let parts = string.split(parsed, "\n---\n")
      case parts {
        [class, reason] -> Ok(#(string.trim(class), string.trim(reason)))
        [class] -> Ok(#(string.trim(class), "No reasoning provided via decision gate."))
        _ -> Ok(#("other", "No reasoning provided via decision gate."))
      }
    }
    Error(e) -> Error(e)
  }
}

fn invoke_refusal_flow(
  issue_str: String,
  class: String,
  reasoning: String,
) -> Result(RefusalResult, String) {
  case config.issue_provider_name() {
    "linear" -> {
      case linear_flow.run_refusal_linear(issue_str, class, reasoning) {
        Ok(res) -> Ok(res)
        Error(e) -> Error(refusal_error_to_string(e))
      }
    }
    _ -> {
      case int.parse(issue_str) {
        Error(_) -> Error("invalid issue: " <> issue_str)
        Ok(issue) -> {
          case flow.run_refusal(issue, class, reasoning) {
            Ok(res) -> Ok(res)
            Error(e) -> Error(refusal_error_to_string(e))
          }
        }
      }
    }
  }
}

fn refusal_error_to_string(e: RefusalError) -> String {
  case e {
    OtherError(m) -> "other: " <> m
    FetchFailed(m) -> "fetch_failed: " <> m
    CheckpointFailed(m) -> "checkpoint_failed: " <> m
    ProjectMoveFailed(m) -> "project_move_failed: " <> m
  }
}
