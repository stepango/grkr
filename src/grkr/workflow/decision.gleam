import gleam/list
import gleam/result
import gleam/string

import grkr/refusal/types.{
  type ImplementationDecision, parse_implementation_decision,
}

/// Ports bash extract_decision_from_output (awk last "proceed" or "refuse" after trim/lower)
pub fn extract_decision_from_output(output: String) -> String {
  output
  |> string.split("\n")
  |> list.reverse
  |> list.find(fn(line) {
    let t = string.trim(line) |> string.lowercase
    t == "proceed" || t == "refuse"
  })
  |> result.map(fn(l) { string.trim(l) |> string.lowercase })
  |> result.unwrap("")
}

/// Ports bash parse_refusal_decision_output
/// Input after "refuse" line: class on next non-empty, then --- then explanation lines
/// Output: "class\n---\nreason" or "other\n---\n" if no reason
pub fn parse_refusal_decision_output(output: String) -> String {
  let lines =
    output
    |> string.split("\n")
    |> list.map(string.trim)

  case find_refusal_line_index(lines) {
    Error(_) -> ""
    Ok(refusal_idx) -> {
      let after = list.drop(lines, refusal_idx + 1)
      let non_empty_after = list.filter(after, fn(l) { l != "" })

      case non_empty_after {
        [] -> "other\n---\n"
        [class_line, ..rest] -> {
          let class = string.trim(class_line)
          let explanation =
            rest
            |> list.filter(fn(l) { l != "" })
            |> string.join("\n")

          case explanation {
            "" -> class <> "\n---\n"
            _ -> class <> "\n---\n" <> explanation
          }
        }
      }
    }
  }
}

fn find_refusal_line_index(lines: List(String)) -> Result(Int, Nil) {
  lines
  |> list.index_map(fn(l, i) { #(i, string.lowercase(l)) })
  |> list.find(fn(pair) {
    let #(_, lower) = pair
    lower == "refuse"
  })
  |> result.map(fn(p) {
    let #(i, _) = p
    i
  })
  |> result.replace_error(Nil)
}

/// Ports bash detect_implementation_refusal (awk on task log stream for marker)
/// Looks for "grkr-refuse-implementation" marker, then class line (one of 7), then reasoning lines
/// Returns "class\n---\nreason" or "" if no marker match
pub fn detect_implementation_refusal(output: String) -> String {
  let lines =
    output
    |> string.split("\n")
    |> list.map(string.trim)

  case find_marker_index(lines) {
    Error(_) -> ""
    Ok(marker_idx) -> {
      let after = list.drop(lines, marker_idx + 1)
      let non_empty = list.filter(after, fn(l) { l != "" })

      case non_empty {
        [] -> ""
        [first, ..rest] -> {
          let lower_first = string.lowercase(first)
          let valid_classes = [
            "underspecified", "too_large", "missing_dependency",
            "needs_design_decision", "unsafe_autonomous_change",
            "repo_not_ready", "other",
          ]

          case list.contains(valid_classes, lower_first) {
            True -> {
              let class = lower_first
              let reasoning =
                rest
                |> list.filter(fn(l) { l != "" })
                |> string.join("\n")

              case reasoning {
                "" ->
                  class
                  <> "\n---\nImplementation discovered that the issue is not ready for safe autonomous completion."
                _ -> class <> "\n---\n" <> reasoning
              }
            }
            False -> ""
          }
        }
      }
    }
  }
}

fn find_marker_index(lines: List(String)) -> Result(Int, Nil) {
  // Codex prompts embed the marker as documentation; the real signal is the
  // last occurrence in the combined prompt+response log (bash parity: awk on stream).
  lines
  |> list.index_map(fn(l, i) {
    let lower = string.trim(l) |> string.lowercase
    #(i, lower)
  })
  |> list.filter(fn(pair) {
    let #(_, lower) = pair
    lower == "grkr-refuse-implementation"
  })
  |> list.last
  |> result.map(fn(p) {
    let #(i, _) = p
    i
  })
  |> result.replace_error(Nil)
}

/// Update progress.json with decision (proceed or refuse) + stage status.
/// Mirrors bash update_task_progress_decision jq exactly (for proceed sets status=implementing)
/// Uses FFI for atomic write (like refusal fs.mjs)
pub fn update_task_progress_decision(
  progress_file: String,
  decision: String,
) -> Result(Nil, String) {
  case decision {
    "proceed" | "refuse" -> ffi_update_progress_decision(progress_file, decision)
    _ -> Error("invalid decision: " <> decision)
  }
}

@external(javascript, "./worktree_ffi.mjs", "update_progress_for_decision")
fn ffi_update_progress_decision(
  progress_file: String,
  decision: String,
) -> Result(Nil, String)

/// High level gate (parse only; actual codex run stays in shell thin per scope)
/// Returns the ImplementationDecision parsed from raw codex output
pub fn run_decision_parse(raw_output: String) -> ImplementationDecision {
  parse_implementation_decision(raw_output)
}

/// CLI entry for decision gate (GitHub-only v2).
/// Subcommands for thin shell callers:
///   decide <output-file>          -> prints "proceed" or "refuse" (for $())
///   parse-refusal <output-file>   -> prints class\n---\nreason
///   detect-refusal <log-file>     -> prints class\n---\nreason or empty
///   update-progress <progress.json> <proceed|refuse>
/// Mirrors old bash fns for callsites in grkr-issue-workflow.sh / bin/grkr
pub fn main() {
  case argv() {
    ["decide", output_file] -> do_decide(output_file)
    ["parse-refusal", output_file] -> do_parse_refusal(output_file)
    ["detect-refusal", log_file] -> do_detect_refusal(log_file)
    ["update-progress", progress_file, decision] ->
      do_update_progress(progress_file, decision)
    ["help"] | [] -> emit_usage()
    _ -> emit_usage()
  }
}

@external(javascript, "./cli_ffi.mjs", "argv")
fn argv() -> List(String)

@external(javascript, "console", "log")
fn console_log(s: String) -> Nil

@external(javascript, "console", "error")
fn console_error(s: String) -> Nil

@external(javascript, "process", "exit")
fn exit(code: Int) -> Nil

fn emit_usage() {
  console_error("Usage: gleam run -m grkr/workflow/decision -- decide <output-file>")
  console_error("       gleam run -m grkr/workflow/decision -- parse-refusal <output-file>")
  console_error("       gleam run -m grkr/workflow/decision -- detect-refusal <log-file>")
  console_error("       gleam run -m grkr/workflow/decision -- update-progress <progress.json> <proceed|refuse>")
  console_error("       gleam run -m grkr/workflow/decision -- help")
  console_error("")
  console_error("Decision gate CLI (GitHub-only v2): pure parse + progress mutation for thin wrappers.")
  console_error("No LLM invocation here (codex stays shell-orchestrated in this slice).")
  exit(2)
}

fn do_decide(output_file: String) {
  case ffi_read_file(output_file) {
    Ok(content) -> {
      let d = extract_decision_from_output(content)
      case d {
        "" -> {
          console_error("❌ No proceed/refuse decision found in " <> output_file)
          exit(1)
        }
        _ -> {
          console_log(d)
          exit(0)
        }
      }
    }
    Error(e) -> {
      console_error("❌ Failed to read " <> output_file <> ": " <> e)
      exit(1)
    }
  }
}

fn do_parse_refusal(output_file: String) {
  case ffi_read_file(output_file) {
    Ok(content) -> {
      let parsed = parse_refusal_decision_output(content)
      console_log(parsed)
      exit(0)
    }
    Error(e) -> {
      console_error("❌ read failed: " <> e)
      exit(1)
    }
  }
}

fn do_detect_refusal(log_file: String) {
  case ffi_read_file(log_file) {
    Ok(content) -> {
      let detected = detect_implementation_refusal(content)
      console_log(detected)
      exit(0)
    }
    Error(e) -> {
      console_error("❌ read failed: " <> e)
      exit(1)
    }
  }
}

fn do_update_progress(progress_file: String, decision: String) {
  case update_task_progress_decision(progress_file, decision) {
    Ok(_) -> {
      console_error("✅ Updated progress decision to " <> decision <> " in " <> progress_file)
      exit(0)
    }
    Error(e) -> {
      console_error("❌ update failed: " <> e)
      exit(1)
    }
  }
}

@external(javascript, "./worktree_ffi.mjs", "read_file")
fn ffi_read_file(path: String) -> Result(String, String)
