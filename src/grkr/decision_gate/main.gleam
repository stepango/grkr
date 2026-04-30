import gleam/io
import grkr/decision_gate/decision
import grkr/decision_gate/refusal
import grkr/decision_gate/types

pub fn main() {
  case javascript_argv() {
    ["parse-decision", output_file] -> parse_decision_command(output_file)
    ["detect-refusal", output_file] -> detect_refusal_command(output_file)
    _ -> {
      io.println("Usage: gleam run -m grkr/decision_gate/main -- parse-decision <output-file> | detect-refusal <output-file>")
      javascript_exit(64)
    }
  }
}

fn parse_decision_command(output_file: String) {
  let result = run_decision_gate(javascript_read_file(output_file))
  io.println(decision_result_to_string(result))
}

fn detect_refusal_command(output_file: String) {
  case refusal.parse_implementation_refusal(javascript_read_file(output_file)) {
    Ok(details) -> {
      io.println(refusal.refusal_class_to_string(details.class))
      io.println("---")
      io.println(details.reasoning)
    }
    Error(_) -> Nil
  }
}

/// Run the decision gate on Codex output.
/// Invalid or ambiguous output fails closed to `refuse`.
pub fn run_decision_gate(codex_output: String) -> types.DecisionResult {
  case decision.parse_decision(codex_output) {
    Ok(types.Proceed) -> types.DecisionProceeded
    Ok(types.Refuse) -> {
      case refusal.parse_refusal_details(codex_output) {
        Ok(details) -> types.DecisionRefused(details)
        Error(_) -> {
          types.DecisionRefused(types.RefusalDetails(
            class: types.Other,
            reasoning: refusal.default_refusal_reasoning(),
          ))
        }
      }
    }
    Error(_) -> {
      types.DecisionRefused(types.RefusalDetails(
        class: types.Other,
        reasoning: "Decision gate returned an invalid result. Defaulting to refuse for safety.",
      ))
    }
  }
}

pub fn create_context(
  issue_number: Int,
  title: String,
  url: String,
  body: String,
  repo_root: String,
  worktree_dir: String,
  task_slug: String,
  max_file_lines: Int,
) -> types.DecisionGateContext {
  types.DecisionGateContext(
    issue: types.IssueContext(
      issue_number: issue_number,
      title: title,
      url: url,
      body: body,
    ),
    repo: types.RepoContext(
      root: repo_root,
      worktree_dir: worktree_dir,
      task_slug: task_slug,
      max_file_lines: max_file_lines,
    ),
  )
}

pub fn is_proceed(result: types.DecisionResult) -> Bool {
  case result {
    types.DecisionProceeded -> True
    _ -> False
  }
}

pub fn is_refuse(result: types.DecisionResult) -> Bool {
  case result {
    types.DecisionRefused(_) -> True
    _ -> False
  }
}

pub fn get_refusal_details(
  result: types.DecisionResult,
) -> Result(types.RefusalDetails, Nil) {
  case result {
    types.DecisionRefused(details) -> Ok(details)
    _ -> Error(Nil)
  }
}

pub fn decision_result_to_string(result: types.DecisionResult) -> String {
  case result {
    types.DecisionProceeded -> "proceed"
    types.DecisionRefused(_) -> "refuse"
  }
}

@external(javascript, "../decision_gate/io.mjs", "read_file")
fn javascript_read_file(path: String) -> String

@external(javascript, "../decision_gate/io.mjs", "argv")
fn javascript_argv() -> List(String)

@external(javascript, "../decision_gate/io.mjs", "exit")
fn javascript_exit(code: Int) -> Nil
